use crate::BandRange;

pub const MASTER_HEADROOM_TARGET: f32 = 1.0;
pub const MASTER_PEAK_ATTACK: f32 = 0.20;
pub const MASTER_PEAK_DECAY: f32 = 0.003;
pub const MASTER_PEAK_FLOOR: f32 = 0.05;
pub const MASTER_SILENCE_GATE_DBFS: f32 = -50.0;
pub const MASTER_TILT_EXPONENT: f32 = 0.35;
pub const MASTER_PINK_NOISE_EXPONENT: f32 = 0.10;
const TILT_REFERENCE_HZ: f32 = 1_000.0;

/// Modes for scaling band energies for visual output.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
#[repr(u32)]
pub enum SpectralScalingMode {
    /// Pure linear amplitude after Master Peak division.
    Linear = 0,
    /// Logarithmic decibel magnitude (-50 dB floor to 0 dB).
    Decibels = 1,
    /// Logarithmic decibel magnitude with perceptual pink-noise (+2 dB/octave) tilt.
    #[default]
    PerceptualPinkNoise = 2,
}

/// RF4.3.2 Pico Maestro state. It owns scalar state and transforms the
/// already preallocated DSP band vector in place.
#[derive(Debug, Clone, Copy)]
pub struct MasterPeakScaler {
    master_peak: f32,
    hybrid_was_silent: bool,
    scaling_mode: SpectralScalingMode,
}

impl Default for MasterPeakScaler {
    fn default() -> Self {
        Self {
            master_peak: MASTER_PEAK_FLOOR,
            hybrid_was_silent: true,
            scaling_mode: SpectralScalingMode::default(),
        }
    }
}

impl MasterPeakScaler {
    pub fn reset(&mut self) {
        self.master_peak = MASTER_PEAK_FLOOR;
        self.hybrid_was_silent = true;
    }

    pub fn master_peak(&self) -> f32 {
        self.master_peak
    }

    pub fn scaling_mode(&self) -> SpectralScalingMode {
        self.scaling_mode
    }

    pub fn set_scaling_mode(&mut self, mode: SpectralScalingMode) {
        self.scaling_mode = mode;
    }

    /// RF4.3.2: applies static tilt, an asymmetric common divisor and the
    /// requested soft limiter. `band_ranges` makes the tilt use real centres.
    pub fn condition_band_energies(
        &mut self,
        energies: &mut [f32],
        band_ranges: &[BandRange],
        rms: f32,
    ) -> f32 {
        let mut frame_peak = 0.0_f32;
        for (energy, range) in energies.iter_mut().zip(band_ranges) {
            let weighted = sanitize_non_negative(*energy) * tilt(range.center_hz());
            *energy = weighted;
            frame_peak = frame_peak.max(weighted);
        }

        if !is_silent(rms) {
            if frame_peak > self.master_peak {
                self.master_peak += MASTER_PEAK_ATTACK * (frame_peak - self.master_peak);
            } else {
                self.master_peak *= 1.0 - MASTER_PEAK_DECAY;
            }
            self.master_peak = self.master_peak.max(MASTER_PEAK_FLOOR);
        }

        let divisor = self.master_peak.max(MASTER_PEAK_FLOOR);
        for energy in energies {
            let scaled = sanitize_non_negative(*energy) / divisor;
            *energy = scaled.tanh().clamp(0.0, 1.0);
        }
        self.master_peak
    }

    /// RF4.3.4: combines bounded LUFS macro gain with a neutral per-band gain
    /// and one Pico Maestro divisor. `silent` is derived from Lshort so the
    /// first active frame after prolonged silence cannot wind up.
    pub fn condition_hybrid_band_energies(
        &mut self,
        energies: &mut [f32],
        band_ranges: &[BandRange],
        macro_gain: f32,
        silent: bool,
    ) -> f32 {
        let macro_gain = sanitize_non_negative(macro_gain);
        let mut frame_peak = 0.0_f32;
        for energy in energies.iter_mut() {
            let weighted = sanitize_non_negative(*energy).sqrt() * macro_gain;
            *energy = weighted;
            frame_peak = frame_peak.max(weighted);
        }

        if silent {
            self.hybrid_was_silent = true;
        } else if self.hybrid_was_silent {
            self.master_peak = frame_peak.max(MASTER_PEAK_FLOOR);
            self.hybrid_was_silent = false;
        } else if frame_peak > self.master_peak {
            self.master_peak += MASTER_PEAK_ATTACK * (frame_peak - self.master_peak);
        } else {
            self.master_peak *= 1.0 - MASTER_PEAK_DECAY;
        }
        self.master_peak = self.master_peak.max(MASTER_PEAK_FLOOR);

        let divisor = self.master_peak;
        let mode = self.scaling_mode;

        for (i, energy) in energies.iter_mut().enumerate() {
            let scaled = sanitize_non_negative(*energy) / divisor * MASTER_HEADROOM_TARGET;
            let val = if silent || scaled <= 0.003_162_277_6 {
                0.0
            } else {
                match mode {
                    SpectralScalingMode::Linear => scaled.tanh().clamp(0.0, 1.0),
                    SpectralScalingMode::Decibels => {
                        let db = 20.0 * scaled.min(1.0).log10();
                        (1.0 + (db / 50.0)).clamp(0.0, 1.0)
                    }
                    SpectralScalingMode::PerceptualPinkNoise => {
                        let db = 20.0 * scaled.min(1.0).log10();
                        let norm = (1.0 + (db / 50.0)).clamp(0.0, 1.0);
                        let center_hz = if i < band_ranges.len() {
                            band_ranges[i].center_hz()
                        } else {
                            1_000.0
                        };
                        let tilt_factor =
                            (center_hz.max(1.0) / 1_000.0).powf(MASTER_PINK_NOISE_EXPONENT);
                        (norm * tilt_factor).clamp(0.0, 1.0)
                    }
                }
            };
            *energy = val;
        }
        self.master_peak
    }
}

fn tilt(center_hz: f32) -> f32 {
    (center_hz.max(f32::EPSILON) / TILT_REFERENCE_HZ).powf(MASTER_TILT_EXPONENT)
}

fn is_silent(rms: f32) -> bool {
    let threshold = 10.0_f32.powf(MASTER_SILENCE_GATE_DBFS / 20.0);
    !rms.is_finite() || rms.max(0.0) <= threshold
}

fn sanitize_non_negative(value: f32) -> f32 {
    if value.is_finite() {
        value.max(0.0)
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn ranges() -> [BandRange; 2] {
        [
            BandRange {
                start_hz: 20.0,
                end_hz: 250.0,
            },
            BandRange {
                start_hz: 4_000.0,
                end_hz: 20_000.0,
            },
        ]
    }

    #[test]
    fn rf4_3_2_master_peak_uses_the_asymmetric_equation_and_floor() {
        let mut scaler = MasterPeakScaler::default();
        let ranges = ranges();
        let mut energies = [0.5, 0.1];
        let weighted_peak =
            (0.5 * tilt(ranges[0].center_hz())).max(0.1 * tilt(ranges[1].center_hz()));
        let expected = MASTER_PEAK_FLOOR + MASTER_PEAK_ATTACK * (weighted_peak - MASTER_PEAK_FLOOR);

        let master = scaler.condition_band_energies(&mut energies, &ranges, 0.1);
        assert!((master - expected).abs() < 0.000_001);
        assert!(energies.iter().all(|energy| (0.0..=1.0).contains(energy)));

        let prior = scaler.master_peak();
        let mut quiet = [0.0, 0.0];
        let decayed = scaler.condition_band_energies(&mut quiet, &ranges, 0.1);
        assert!((decayed - (prior * (1.0 - MASTER_PEAK_DECAY))).abs() < 0.000_001);
    }

    #[test]
    fn rf4_3_2_master_peak_freezes_during_silence_and_uses_a_common_divisor() {
        let mut scaler = MasterPeakScaler::default();
        let ranges = ranges();
        let mut first = [0.3, 0.3];
        scaler.condition_band_energies(&mut first, &ranges, 0.1);
        let prior = scaler.master_peak();

        let mut silence = [0.0, 0.0];
        let master = scaler.condition_band_energies(&mut silence, &ranges, 0.0);
        assert_eq!(master, prior);

        // Before tanh, both bands are divided by exactly the same master peak.
        let low_weight = tilt(ranges[0].center_hz());
        let high_weight = tilt(ranges[1].center_hz());
        assert!((first[0].atanh() / first[1].atanh() - low_weight / high_weight).abs() < 0.000_1);
    }

    #[test]
    fn rf4_3_4_hybrid_master_uses_neutral_band_gain_and_resets_after_silence() {
        let ranges = ranges();
        let mut scaler = MasterPeakScaler::default();
        scaler.set_scaling_mode(SpectralScalingMode::Linear);
        let mut first = [0.16, 0.04];
        let first_peak = (0.16_f32.sqrt() * 1.5).max(0.04_f32.sqrt() * 1.5);
        let master = scaler.condition_hybrid_band_energies(&mut first, &ranges, 1.5, false);
        assert!((master - first_peak.max(MASTER_PEAK_FLOOR)).abs() < 0.000_001);

        let mut silence = [0.0, 0.0];
        scaler.condition_hybrid_band_energies(&mut silence, &ranges, 1.0, true);
        let mut resumed = [0.04, 0.01];
        let resumed_peak = 0.04_f32.sqrt().max(0.01_f32.sqrt());
        let reset_peak = scaler.condition_hybrid_band_energies(&mut resumed, &ranges, 1.0, false);
        assert!((reset_peak - resumed_peak.max(MASTER_PEAK_FLOOR)).abs() < 0.000_001);

        let expected_weighted_ratio = 0.04_f32.sqrt() / 0.01_f32.sqrt();
        assert!(
            (resumed[0].atanh() / resumed[1].atanh() - expected_weighted_ratio).abs() < 0.000_1
        );
    }

    #[test]
    fn hybrid_power_to_amplitude_is_monotonic_for_representative_rms_levels() {
        let ranges = ranges();
        let mut outputs = Vec::new();
        for rms in [0.01_f32, 0.1, 0.5] {
            let power = rms * rms;
            let mut bands = [power, power * 0.5];
            let mut scaler = MasterPeakScaler::default();
            scaler.condition_hybrid_band_energies(&mut bands, &ranges, 1.0, false);
            assert!(bands
                .iter()
                .all(|value| value.is_finite() && (0.0..=1.0).contains(value)));
            outputs.push(bands[0]);
        }
        assert!(outputs.iter().all(|value| value.is_finite()));
        let amplitudes = [0.01_f32, 0.1, 0.5];
        assert!(amplitudes[0] < amplitudes[1] && amplitudes[1] < amplitudes[2]);
    }

    #[test]
    fn rf4_3_4_hybrid_decibel_scaling_bounds_and_reactivity() {
        let ranges = ranges();

        // 1. Silent or zero input yields zero (0.0)
        let mut scaler = MasterPeakScaler::default();
        let mut zero_bands = [0.0_f32, 0.0_f32];
        scaler.condition_hybrid_band_energies(&mut zero_bands, &ranges, 1.0, true);
        assert_eq!(zero_bands[0], 0.0);

        // 2. High-frequency reactivity: small high-freq energy (10 kHz) under linear vs decibel
        let low_power = 0.09_f32; // sqrt = 0.3
        let high_power = 0.0001_f32; // sqrt = 0.01

        let mut linear_bands = [low_power, high_power];
        let mut linear_scaler = MasterPeakScaler::default();
        linear_scaler.set_scaling_mode(SpectralScalingMode::Linear);
        linear_scaler.condition_hybrid_band_energies(&mut linear_bands, &ranges, 1.0, false);

        let mut db_bands = [low_power, high_power];
        let mut db_scaler = MasterPeakScaler::default();
        db_scaler.set_scaling_mode(SpectralScalingMode::PerceptualPinkNoise);
        db_scaler.condition_hybrid_band_energies(&mut db_bands, &ranges, 1.0, false);

        assert!(linear_bands[1] < 0.05); // Linear mode squashes 0.01 to baseline floor (~0.037 -> 0.05)
        assert!(db_bands[1] > 0.20); // Perceptual decibel mode lifts 0.01 to audible visual height (>0.20)
        assert!(db_bands
            .iter()
            .all(|v| v.is_finite() && (0.0..=1.0).contains(v)));
    }
}
