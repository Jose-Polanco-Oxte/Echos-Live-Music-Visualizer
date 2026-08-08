use std::{collections::VecDeque, sync::Arc};

use rustfft::{num_complex::Complex32, Fft, FftPlanner};
use thiserror::Error;

const MIN_AUDIBLE_FREQUENCY_HZ: f32 = 20.0;
const MAX_AUDIBLE_FREQUENCY_HZ: f32 = 20_000.0;
const DEFAULT_LOW_FREQUENCY_DECAY: f32 = 0.15;
const MAX_HIGH_FREQUENCY_DECAY: f32 = 0.80;
const ONSET_HISTORY_LENGTH: usize = 30;
const ONSET_MINIMUM_HISTORY: usize = 3;
const ONSET_SENSITIVITY: f32 = 1.5;
const ONSET_FLOOR: f32 = 0.01;

/// Frequency distribution requested by a visualizer.
///
/// Three-band configurations always use the required fixed 20–250 Hz,
/// 250–4000 Hz and 4000–20000 Hz ranges. The scale is used for configurations
/// with more than three bands.
#[repr(u8)]
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BandScale {
    Linear = 0,
    Logarithmic = 1,
    Mel = 2,
}

#[derive(Debug, Clone)]
pub struct DspSettings {
    pub sample_rate: u32,
    pub frame_size: usize,
    pub band_count: usize,
    pub band_scale: BandScale,
    /// Weight applied when an energy value grows. `1.0` is instantaneous.
    pub attack: f32,
    /// Maximum decay weight at 20 kHz. Lower frequencies are interpolated from
    /// the fixed 0.15 coefficient required by RF2.2.
    pub decay: f32,
}

impl Default for DspSettings {
    fn default() -> Self {
        Self {
            sample_rate: 48_000,
            frame_size: 1_024,
            band_count: 3,
            band_scale: BandScale::Logarithmic,
            attack: 1.0,
            decay: MAX_HIGH_FREQUENCY_DECAY,
        }
    }
}

impl DspSettings {
    pub fn validate(&self) -> Result<(), DspSettingsError> {
        if !(40_001..=192_000).contains(&self.sample_rate) {
            return Err(DspSettingsError::UnsupportedSampleRate(self.sample_rate));
        }

        if !(512..=1_024).contains(&self.frame_size) || !self.frame_size.is_power_of_two() {
            return Err(DspSettingsError::UnsupportedFrameSize(self.frame_size));
        }

        if !(3..=128).contains(&self.band_count) {
            return Err(DspSettingsError::UnsupportedBandCount(self.band_count));
        }

        validate_unit_interval("attack", self.attack)?;

        if !self.decay.is_finite()
            || !(DEFAULT_LOW_FREQUENCY_DECAY..=MAX_HIGH_FREQUENCY_DECAY).contains(&self.decay)
        {
            return Err(DspSettingsError::InvalidDecay(self.decay));
        }

        Ok(())
    }
}

fn validate_unit_interval(name: &'static str, value: f32) -> Result<(), DspSettingsError> {
    if value.is_finite() && (0.0..=1.0).contains(&value) {
        Ok(())
    } else {
        Err(DspSettingsError::InvalidUnitInterval { name, value })
    }
}

#[derive(Debug, Error, PartialEq)]
pub enum DspSettingsError {
    #[error("sample rate {0} Hz cannot represent the 20 Hz–20 kHz DSP range")]
    UnsupportedSampleRate(u32),
    #[error("frame size {0} must be a power of two from 512 through 1024")]
    UnsupportedFrameSize(usize),
    #[error("band count {0} must be from 3 through 128")]
    UnsupportedBandCount(usize),
    #[error("{name} must be finite and in the inclusive range [0.0, 1.0], got {value}")]
    InvalidUnitInterval { name: &'static str, value: f32 },
    #[error("decay must be finite and in the inclusive range [0.15, 0.80], got {0}")]
    InvalidDecay(f32),
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum ProcessError {
    #[error("expected {expected} samples, received {actual}")]
    InvalidFrameLength { expected: usize, actual: usize },
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BandRange {
    pub start_hz: f32,
    pub end_hz: f32,
}

impl BandRange {
    pub fn center_hz(self) -> f32 {
        // Geometric centers preserve the perceptual spacing used for inertia.
        (self.start_hz * self.end_hz).sqrt()
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct ProcessedFrame {
    pub rms: f32,
    pub spectral_centroid_hz: f32,
    pub onset_detected: bool,
    pub band_energies: Vec<f32>,
}

impl ProcessedFrame {
    /// Creates a reusable destination for [`DspProcessor::process_into`].
    pub fn with_band_count(band_count: usize) -> Self {
        Self {
            rms: 0.0,
            spectral_centroid_hz: 0.0,
            onset_detected: false,
            band_energies: vec![0.0; band_count],
        }
    }
}

pub struct DspProcessor {
    settings: DspSettings,
    window: Vec<f32>,
    fft: Arc<dyn Fft<f32>>,
    fft_buffer: Vec<Complex32>,
    magnitudes: Vec<f32>,
    band_ranges: Vec<BandRange>,
    raw_band_energies: Vec<f32>,
    smoothed_bands: Vec<f32>,
    previous_spectrum: Vec<f32>,
    flux_history: VecDeque<f32>,
    magnitude_normalizer: f32,
}

impl DspProcessor {
    pub fn new(settings: DspSettings) -> Result<Self, DspSettingsError> {
        settings.validate()?;

        let window = hamming_window(settings.frame_size);
        let window_gain = window.iter().sum::<f32>() / settings.frame_size as f32;
        let magnitude_normalizer =
            (settings.frame_size as f32 * window_gain * 0.5).max(f32::EPSILON);
        let band_ranges = calculate_band_ranges(&settings);
        let mut planner = FftPlanner::<f32>::new();

        Ok(Self {
            fft: planner.plan_fft_forward(settings.frame_size),
            fft_buffer: vec![Complex32::default(); settings.frame_size],
            magnitudes: vec![0.0; settings.frame_size / 2 + 1],
            raw_band_energies: vec![0.0; settings.band_count],
            smoothed_bands: vec![0.0; settings.band_count],
            previous_spectrum: vec![0.0; settings.frame_size / 2 + 1],
            flux_history: VecDeque::with_capacity(ONSET_HISTORY_LENGTH),
            settings,
            window,
            band_ranges,
            magnitude_normalizer,
        })
    }

    pub fn settings(&self) -> &DspSettings {
        &self.settings
    }

    pub fn band_ranges(&self) -> &[BandRange] {
        &self.band_ranges
    }

    /// Processes one frame and returns an owned snapshot for simple callers.
    /// For a real-time path, use [`Self::process_into`] with a reused frame.
    pub fn process(&mut self, samples: &[f32]) -> Result<ProcessedFrame, ProcessError> {
        let mut frame = ProcessedFrame::with_band_count(self.settings.band_count);
        self.process_into(samples, &mut frame)?;
        Ok(frame)
    }

    /// Processes one frame without allocating DSP working buffers. `output` is
    /// resized only if the caller did not preallocate it with the band count.
    pub fn process_into(
        &mut self,
        samples: &[f32],
        output: &mut ProcessedFrame,
    ) -> Result<(), ProcessError> {
        if samples.len() != self.settings.frame_size {
            return Err(ProcessError::InvalidFrameLength {
                expected: self.settings.frame_size,
                actual: samples.len(),
            });
        }

        let rms = self.populate_fft_buffer_and_calculate_rms(samples);
        self.fft.process(&mut self.fft_buffer);
        self.populate_magnitudes();

        let spectral_centroid_hz = spectral_centroid(
            &self.magnitudes,
            self.settings.sample_rate,
            self.settings.frame_size,
        );
        let onset_detected = self.detect_onset();
        self.aggregate_bands();
        self.smooth_bands();

        output.rms = sanitize_non_negative(rms);
        output.spectral_centroid_hz = sanitize_non_negative(spectral_centroid_hz);
        output.onset_detected = onset_detected;
        if output.band_energies.len() != self.smoothed_bands.len() {
            output.band_energies.resize(self.smoothed_bands.len(), 0.0);
        }
        output.band_energies.copy_from_slice(&self.smoothed_bands);
        Ok(())
    }

    fn populate_fft_buffer_and_calculate_rms(&mut self, samples: &[f32]) -> f32 {
        let mut square_sum = 0.0;
        for ((fft_value, window), sample) in
            self.fft_buffer.iter_mut().zip(&self.window).zip(samples)
        {
            let sample = sanitize_sample(*sample);
            square_sum += sample * sample;
            *fft_value = Complex32::new(sample * window, 0.0);
        }
        (square_sum / samples.len() as f32).sqrt()
    }

    fn populate_magnitudes(&mut self) {
        for (magnitude, fft_value) in self.magnitudes.iter_mut().zip(&self.fft_buffer) {
            *magnitude = sanitize_non_negative(fft_value.norm());
        }
    }

    fn aggregate_bands(&mut self) {
        // RF1.3: sample the FFT continuously inside each configured range.
        // A narrow logarithmic band therefore interpolates adjacent bins instead
        // of becoming structurally empty when no bin centre lies inside it.
        for (energy, range) in self.raw_band_energies.iter_mut().zip(&self.band_ranges) {
            *energy = continuous_band_energy(
                &self.magnitudes,
                *range,
                self.settings.sample_rate,
                self.settings.frame_size,
                self.magnitude_normalizer,
            );
        }
    }

    fn smooth_bands(&mut self) {
        let high_frequency_decay = self.settings.decay;
        for ((raw, smoothed), range) in self
            .raw_band_energies
            .iter()
            .zip(&mut self.smoothed_bands)
            .zip(&self.band_ranges)
        {
            let alpha = if raw > smoothed {
                self.settings.attack
            } else {
                frequency_decay_alpha(range.center_hz(), high_frequency_decay)
            };
            *smoothed = sanitize_unit_interval(alpha * raw + (1.0 - alpha) * *smoothed);
        }
    }

    fn detect_onset(&mut self) -> bool {
        let flux = self
            .magnitudes
            .iter()
            .zip(&self.previous_spectrum)
            .map(|(current, previous)| (current - previous).max(0.0))
            .sum::<f32>();
        self.previous_spectrum.copy_from_slice(&self.magnitudes);

        // Compare to prior frames only: including the current transient in its
        // own baseline suppresses exactly the event the visualizers need.
        let onset = if self.flux_history.len() >= ONSET_MINIMUM_HISTORY {
            let mean = self.flux_history.iter().sum::<f32>() / self.flux_history.len() as f32;
            let variance = self
                .flux_history
                .iter()
                .map(|value| (value - mean).powi(2))
                .sum::<f32>()
                / self.flux_history.len() as f32;
            flux > mean + ONSET_SENSITIVITY * variance.sqrt() + ONSET_FLOOR
        } else {
            false
        };

        if self.flux_history.len() == ONSET_HISTORY_LENGTH {
            self.flux_history.pop_front();
        }
        self.flux_history.push_back(sanitize_non_negative(flux));
        onset
    }
}

fn hamming_window(frame_size: usize) -> Vec<f32> {
    (0..frame_size)
        .map(|index| {
            let phase = 2.0 * std::f32::consts::PI * index as f32 / (frame_size - 1) as f32;
            0.54 - 0.46 * phase.cos()
        })
        .collect()
}

fn calculate_band_ranges(settings: &DspSettings) -> Vec<BandRange> {
    let max_frequency_hz = (settings.sample_rate as f32 * 0.5).min(MAX_AUDIBLE_FREQUENCY_HZ);
    if settings.band_count == 3 {
        return vec![
            BandRange {
                start_hz: MIN_AUDIBLE_FREQUENCY_HZ,
                end_hz: 250.0,
            },
            BandRange {
                start_hz: 250.0,
                end_hz: 4_000.0,
            },
            BandRange {
                start_hz: 4_000.0,
                end_hz: max_frequency_hz,
            },
        ];
    }

    (0..=settings.band_count)
        .map(|index| {
            scale_edge(
                index,
                settings.band_count,
                settings.band_scale,
                max_frequency_hz,
            )
        })
        .collect::<Vec<_>>()
        .windows(2)
        .map(|edge| BandRange {
            start_hz: edge[0],
            end_hz: edge[1],
        })
        .collect()
}

fn scale_edge(index: usize, band_count: usize, scale: BandScale, max_frequency_hz: f32) -> f32 {
    let position = index as f32 / band_count as f32;
    match scale {
        BandScale::Linear => {
            MIN_AUDIBLE_FREQUENCY_HZ + (max_frequency_hz - MIN_AUDIBLE_FREQUENCY_HZ) * position
        }
        BandScale::Logarithmic => {
            MIN_AUDIBLE_FREQUENCY_HZ * (max_frequency_hz / MIN_AUDIBLE_FREQUENCY_HZ).powf(position)
        }
        BandScale::Mel => {
            let min_mel = hz_to_mel(MIN_AUDIBLE_FREQUENCY_HZ);
            let max_mel = hz_to_mel(max_frequency_hz);
            mel_to_hz(min_mel + (max_mel - min_mel) * position)
        }
    }
}

fn continuous_band_energy(
    magnitudes: &[f32],
    range: BandRange,
    sample_rate: u32,
    frame_size: usize,
    magnitude_normalizer: f32,
) -> f32 {
    let bin_width_hz = sample_rate as f32 / frame_size as f32;
    let sample_count = ((range.end_hz - range.start_hz) / bin_width_hz)
        .ceil()
        .max(1.0) as usize;
    let mut squared_sum = 0.0;

    for index in 0..sample_count {
        let frequency_hz = range.start_hz
            + (index as f32 + 0.5) / sample_count as f32 * (range.end_hz - range.start_hz);
        let magnitude = interpolate_magnitude(magnitudes, frequency_hz / bin_width_hz);
        squared_sum += magnitude * magnitude;
    }

    sanitize_unit_interval((squared_sum / sample_count as f32).sqrt() / magnitude_normalizer)
}

fn interpolate_magnitude(magnitudes: &[f32], fractional_bin: f32) -> f32 {
    if magnitudes.is_empty() || !fractional_bin.is_finite() {
        return 0.0;
    }

    let lower = fractional_bin.floor().max(0.0) as usize;
    let lower = lower.min(magnitudes.len() - 1);
    let upper = (lower + 1).min(magnitudes.len() - 1);
    let fraction = (fractional_bin - lower as f32).clamp(0.0, 1.0);
    sanitize_non_negative(magnitudes[lower] * (1.0 - fraction) + magnitudes[upper] * fraction)
}

const LN_MIN_AUDIBLE_HZ: f32 = 2.995_732_3;
const INV_LN_AUDIBLE_RANGE: f32 = 0.144_764_83;

fn frequency_decay_alpha(frequency_hz: f32, high_frequency_decay: f32) -> f32 {
    let clamped_frequency = frequency_hz.clamp(MIN_AUDIBLE_FREQUENCY_HZ, MAX_AUDIBLE_FREQUENCY_HZ);
    let position = (clamped_frequency.ln() - LN_MIN_AUDIBLE_HZ) * INV_LN_AUDIBLE_RANGE;
    DEFAULT_LOW_FREQUENCY_DECAY + (high_frequency_decay - DEFAULT_LOW_FREQUENCY_DECAY) * position
}

fn hz_to_mel(frequency_hz: f32) -> f32 {
    2_595.0 * (1.0 + frequency_hz / 700.0).log10()
}

fn mel_to_hz(mel: f32) -> f32 {
    700.0 * (10.0_f32.powf(mel / 2_595.0) - 1.0)
}

fn spectral_centroid(magnitudes: &[f32], sample_rate: u32, frame_size: usize) -> f32 {
    let magnitude_sum = magnitudes.iter().sum::<f32>();
    if magnitude_sum <= f32::EPSILON || !magnitude_sum.is_finite() {
        return 0.0;
    }

    magnitudes
        .iter()
        .enumerate()
        .map(|(bin, magnitude)| {
            bin as f32 * sample_rate as f32 / frame_size as f32 * sanitize_non_negative(*magnitude)
        })
        .sum::<f32>()
        / magnitude_sum
}

fn sanitize_sample(sample: f32) -> f32 {
    if sample.is_finite() {
        sample
    } else {
        0.0
    }
}

fn sanitize_non_negative(value: f32) -> f32 {
    if value.is_finite() {
        value.max(0.0)
    } else {
        0.0
    }
}

fn sanitize_unit_interval(value: f32) -> f32 {
    if value.is_finite() {
        value.clamp(0.0, 1.0)
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use approx::assert_abs_diff_eq;

    use super::*;

    fn processor(settings: DspSettings) -> DspProcessor {
        DspProcessor::new(settings).expect("test settings must be valid")
    }

    fn sine_wave(frequency_hz: f32, amplitude: f32, settings: &DspSettings) -> Vec<f32> {
        (0..settings.frame_size)
            .map(|sample| {
                amplitude
                    * (2.0 * std::f32::consts::PI * frequency_hz * sample as f32
                        / settings.sample_rate as f32)
                        .sin()
            })
            .collect()
    }

    #[test]
    fn default_settings_use_the_required_three_bands() {
        let processor = processor(DspSettings::default());
        assert_eq!(processor.settings().band_count, 3);
        assert_eq!(
            processor.band_ranges(),
            [
                BandRange {
                    start_hz: 20.0,
                    end_hz: 250.0,
                },
                BandRange {
                    start_hz: 250.0,
                    end_hz: 4_000.0,
                },
                BandRange {
                    start_hz: 4_000.0,
                    end_hz: 20_000.0,
                },
            ]
        );
    }

    #[test]
    fn rejects_invalid_settings_without_panicking() {
        let settings = DspSettings {
            frame_size: 768,
            ..DspSettings::default()
        };
        assert!(matches!(
            DspProcessor::new(settings),
            Err(DspSettingsError::UnsupportedFrameSize(768))
        ));

        let settings = DspSettings {
            attack: f32::NAN,
            ..DspSettings::default()
        };
        assert!(matches!(
            DspProcessor::new(settings),
            Err(DspSettingsError::InvalidUnitInterval { name: "attack", .. })
        ));
    }

    #[test]
    fn stft_concentrates_a_one_kilohertz_tone_near_its_bin() {
        let settings = DspSettings::default();
        let mut processor = processor(settings.clone());
        processor
            .process(&sine_wave(1_000.0, 1.0, &settings))
            .unwrap();
        let strongest_bin = processor
            .magnitudes
            .iter()
            .enumerate()
            .max_by(|(_, left), (_, right)| left.total_cmp(right))
            .map(|(index, _)| index)
            .unwrap();
        let expected_bin =
            (1_000.0 * settings.frame_size as f32 / settings.sample_rate as f32).round() as usize;
        assert!((strongest_bin as isize - expected_bin as isize).abs() <= 1);
    }

    #[test]
    fn hamming_window_reduces_non_tonal_leakage_by_at_least_thirty_decibels() {
        let settings = DspSettings::default();
        let samples = sine_wave(1_013.0, 1.0, &settings);
        let windowed = transform_magnitudes(&samples, &hamming_window(settings.frame_size));
        let rectangular = transform_magnitudes(&samples, &vec![1.0; settings.frame_size]);
        let windowed_leakage = maximum_distant_bin(&windowed, 4);
        let rectangular_leakage = maximum_distant_bin(&rectangular, 4);
        let attenuation_db = 20.0 * (maximum_bin(&windowed) / windowed_leakage).log10();
        assert!(
            attenuation_db >= 30.0,
            "Hamming side-lobe attenuation was {attenuation_db} dB"
        );
        assert!(windowed_leakage < rectangular_leakage);
    }

    #[test]
    fn all_scales_cover_the_audible_range_for_dynamic_band_counts() {
        for band_count in [3, 12, 64, 128] {
            for scale in [BandScale::Linear, BandScale::Logarithmic, BandScale::Mel] {
                let settings = DspSettings {
                    band_count,
                    band_scale: scale,
                    ..DspSettings::default()
                };
                let processor = processor(settings);
                assert_eq!(processor.band_ranges().len(), band_count);
                assert_abs_diff_eq!(processor.band_ranges()[0].start_hz, 20.0, epsilon = 0.01);
                assert_abs_diff_eq!(
                    processor.band_ranges().last().unwrap().end_hz,
                    20_000.0,
                    epsilon = 0.01
                );
                assert!(processor.band_ranges().iter().all(|range| {
                    range.start_hz >= MIN_AUDIBLE_FREQUENCY_HZ && range.end_hz <= 20_000.0
                }));
            }
        }
    }

    #[test]
    fn interpolates_magnitude_between_adjacent_fft_bins() {
        assert_abs_diff_eq!(interpolate_magnitude(&[0.0, 1.0, 0.0], 0.5), 0.5);
        assert_abs_diff_eq!(interpolate_magnitude(&[0.0, 1.0, 0.0], 1.25), 0.75);
        assert_eq!(interpolate_magnitude(&[], 1.0), 0.0);
    }

    #[test]
    fn continuous_aggregation_covers_every_logarithmic_low_band() {
        let settings = DspSettings {
            band_count: 20,
            band_scale: BandScale::Logarithmic,
            ..DspSettings::default()
        };
        let mut processor = processor(settings);
        processor.magnitudes.fill(processor.magnitude_normalizer);
        processor.aggregate_bands();

        assert!(processor
            .raw_band_energies
            .iter()
            .all(|energy| *energy > 0.99));
        // These were structurally empty with discrete 46.875 Hz bin assignment.
        assert!(processor.raw_band_energies[0] > 0.99);
        assert!(processor.raw_band_energies[1] > 0.99);
        assert!(processor.raw_band_energies[3] > 0.99);
    }

    #[test]
    fn logarithmic_band_centres_react_to_low_frequency_tones() {
        let settings = DspSettings {
            band_count: 20,
            band_scale: BandScale::Logarithmic,
            ..DspSettings::default()
        };
        for band_index in [0, 1, 3] {
            let mut processor = processor(settings.clone());
            let centre_hz = processor.band_ranges()[band_index].center_hz();
            processor
                .process(&sine_wave(centre_hz, 1.0, &settings))
                .unwrap();
            assert!(
                processor.raw_band_energies[band_index] > 0.001,
                "band {} at {centre_hz} Hz did not receive interpolated energy",
                band_index + 1
            );
        }
    }

    #[test]
    fn frequency_dependent_decay_matches_the_specification_endpoints() {
        assert_abs_diff_eq!(frequency_decay_alpha(20.0, 0.80), 0.15, epsilon = 0.001);
        assert_abs_diff_eq!(frequency_decay_alpha(20_000.0, 0.80), 0.80, epsilon = 0.001);
        assert!(frequency_decay_alpha(100.0, 0.80) < frequency_decay_alpha(10_000.0, 0.80));
    }

    #[test]
    fn asymmetric_smoothing_has_instant_attack_and_progressive_decay() {
        let settings = DspSettings::default();
        let mut processor = processor(settings.clone());
        processor.raw_band_energies.fill(1.0);
        processor.smooth_bands();
        assert!(processor.smoothed_bands.iter().all(|energy| *energy == 1.0));

        processor.raw_band_energies.fill(0.0);
        processor.smooth_bands();
        assert!(processor
            .smoothed_bands
            .iter()
            .all(|energy| *energy > 0.0 && *energy < 1.0));
    }

    #[test]
    fn calculates_rms_and_moves_centroid_with_frequency() {
        let settings = DspSettings::default();
        let low = processor(settings.clone())
            .process(&sine_wave(200.0, 1.0, &settings))
            .unwrap();
        let high = processor(settings.clone())
            .process(&sine_wave(8_000.0, 1.0, &settings))
            .unwrap();

        assert_abs_diff_eq!(low.rms, std::f32::consts::FRAC_1_SQRT_2, epsilon = 0.002);
        assert!(
            high.spectral_centroid_hz > low.spectral_centroid_hz + 5_000.0,
            "expected high centroid {} Hz to exceed low centroid {} Hz by 5 kHz",
            high.spectral_centroid_hz,
            low.spectral_centroid_hz
        );
    }

    #[test]
    fn onset_detects_only_the_transient_frame() {
        let settings = DspSettings::default();
        let mut processor = processor(settings.clone());
        let silence = vec![0.0; settings.frame_size];
        for _ in 0..ONSET_MINIMUM_HISTORY {
            assert!(!processor.process(&silence).unwrap().onset_detected);
        }

        let transient = sine_wave(1_000.0, 1.0, &settings);
        assert!(processor.process(&transient).unwrap().onset_detected);
        assert!(!processor.process(&transient).unwrap().onset_detected);
    }

    #[test]
    fn non_finite_samples_are_replaced_with_silence() {
        let settings = DspSettings::default();
        let mut samples = vec![0.0; settings.frame_size];
        samples[0] = f32::NAN;
        samples[1] = f32::INFINITY;
        samples[2] = f32::NEG_INFINITY;
        let frame = processor(settings).process(&samples).unwrap();
        assert_eq!(frame.rms, 0.0);
        assert_eq!(frame.spectral_centroid_hz, 0.0);
        assert!(frame.band_energies.iter().all(|energy| *energy == 0.0));
    }

    #[test]
    fn process_into_reuses_its_output_buffer() {
        let settings = DspSettings::default();
        let mut processor = processor(settings.clone());
        let mut output = ProcessedFrame::with_band_count(settings.band_count);
        let allocation = output.band_energies.as_ptr();
        processor
            .process_into(&vec![0.0; settings.frame_size], &mut output)
            .unwrap();
        assert_eq!(allocation, output.band_energies.as_ptr());
    }

    #[test]
    fn rejects_wrong_input_length() {
        let mut processor = processor(DspSettings::default());
        assert_eq!(
            processor.process(&[0.0; 10]),
            Err(ProcessError::InvalidFrameLength {
                expected: 1_024,
                actual: 10,
            })
        );
    }

    fn transform_magnitudes(samples: &[f32], window: &[f32]) -> Vec<f32> {
        let mut values: Vec<_> = samples
            .iter()
            .zip(window)
            .map(|(sample, window)| Complex32::new(sample * window, 0.0))
            .collect();
        FftPlanner::<f32>::new()
            .plan_fft_forward(values.len())
            .process(&mut values);
        values[..=values.len() / 2]
            .iter()
            .map(|value| value.norm())
            .collect()
    }

    fn maximum_distant_bin(magnitudes: &[f32], excluded_neighbors: usize) -> f32 {
        let strongest = magnitudes
            .iter()
            .enumerate()
            .max_by(|(_, left), (_, right)| left.total_cmp(right))
            .map(|(index, _)| index)
            .unwrap();
        magnitudes
            .iter()
            .enumerate()
            .filter(|(index, _)| index.abs_diff(strongest) > excluded_neighbors)
            .map(|(_, value)| *value)
            .fold(0.0, f32::max)
    }

    fn maximum_bin(magnitudes: &[f32]) -> f32 {
        magnitudes.iter().copied().fold(0.0, f32::max)
    }
}
