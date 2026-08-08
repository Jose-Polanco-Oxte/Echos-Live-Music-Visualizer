use std::collections::VecDeque;

const STAGE1_B0: f64 = 1.535_124_859_586_97;
const STAGE1_B1: f64 = -2.691_696_189_406_38;
const STAGE1_B2: f64 = 1.198_392_810_852_85;
const STAGE1_A1: f64 = -1.690_659_293_182_41;
const STAGE1_A2: f64 = 0.732_480_774_215_85;
const STAGE2_B0: f64 = 1.0;
const STAGE2_B1: f64 = -2.0;
const STAGE2_B2: f64 = 1.0;
const STAGE2_A1: f64 = -1.990_047_454_833_98;
const STAGE2_A2: f64 = 0.990_072_250_366_21;
const SHORT_TERM_WINDOW_SECONDS: usize = 3;
const SILENCE_LUFS: f32 = -70.0;
const STABILIZED_SILENCE_GATE_DBFS: f32 = -50.0;
const STABILIZED_GAMMA_DEADBAND_LU: f32 = 1.5;
const STABILIZED_PIVOT: f32 = 0.02;
const HYBRID_SILENCE_GATE_LUFS: f32 = -50.0;
const HYBRID_GAIN_DEADBAND_LU: f32 = 2.0;
const HYBRID_GAIN_MIN: f32 = 0.5;
const HYBRID_GAIN_MAX: f32 = 2.0;
const HYBRID_GAIN_SMOOTHING_ALPHA: f32 = 0.01;

#[derive(Debug, Clone, Copy, PartialEq)]
pub enum LufsMode {
    Manual {
        gain: f32,
        gamma: f32,
    },
    Automatic {
        target_lufs: f32,
        base_gamma: f32,
        max_gamma: f32,
        sigma_lufs: f32,
        smoothing_alpha: f32,
    },
}

impl Default for LufsMode {
    fn default() -> Self {
        Self::Automatic {
            // RF4.3 normative automatic calibration defaults.
            target_lufs: -14.0,
            base_gamma: 1.0,
            max_gamma: 2.2,
            sigma_lufs: 6.0,
            smoothing_alpha: 0.03,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct LoudnessAdjustment {
    pub short_term_lufs: f32,
    pub gain: f32,
    pub gamma: f32,
}

#[derive(Default)]
struct Biquad {
    x1: f64,
    x2: f64,
    y1: f64,
    y2: f64,
}

impl Biquad {
    fn process(&mut self, sample: f32, coefficients: [f64; 5]) -> f32 {
        let [b0, b1, b2, a1, a2] = coefficients;
        let x = f64::from(sanitize_sample(sample));
        let y = b0 * x + b1 * self.x1 + b2 * self.x2 - a1 * self.y1 - a2 * self.y2;
        self.x2 = self.x1;
        self.x1 = x;
        self.y2 = self.y1;
        self.y1 = y;
        if y.is_finite() {
            y as f32
        } else {
            0.0
        }
    }
}

/// Stateful BS.1770-4 short-term loudness and output conditioning.
pub struct LoudnessProcessor {
    sample_rate_hz: u32,
    stage1: Biquad,
    stage2: Biquad,
    squared_window: VecDeque<f32>,
    squared_sum: f64,
    smoothed_gain: f32,
    smoothed_gamma: f32,
}

impl LoudnessProcessor {
    pub fn new(sample_rate_hz: u32) -> Self {
        Self {
            sample_rate_hz,
            stage1: Biquad::default(),
            stage2: Biquad::default(),
            squared_window: VecDeque::with_capacity(
                sample_rate_hz as usize * SHORT_TERM_WINDOW_SECONDS,
            ),
            squared_sum: 0.0,
            smoothed_gain: 1.0,
            smoothed_gamma: 1.0,
        }
    }

    pub fn process_samples(&mut self, samples: &[f32], mode: LufsMode) -> LoudnessAdjustment {
        self.accumulate_weighted_samples(samples);
        let short_term_lufs = self.short_term_lufs();
        let (gain, gamma) = match mode {
            LufsMode::Manual { gain, gamma } => {
                (sanitize_non_negative(gain), sanitize_gamma(gamma))
            }
            LufsMode::Automatic {
                target_lufs,
                base_gamma,
                max_gamma,
                sigma_lufs,
                smoothing_alpha,
            } => self.automatic_adjustment(
                short_term_lufs,
                target_lufs,
                base_gamma,
                max_gamma,
                sigma_lufs,
                smoothing_alpha,
            ),
        };
        LoudnessAdjustment {
            short_term_lufs,
            gain,
            gamma,
        }
    }

    /// RF4.3.2 mode A. Silence never winds the LUFS IIR upward; active audio
    /// applies a 1.5 LU gamma deadband before the pivoted output curve.
    pub fn process_stabilized_samples(
        &mut self,
        samples: &[f32],
        mode: LufsMode,
    ) -> LoudnessAdjustment {
        if is_below_stabilized_silence_gate(samples) {
            self.reset_stabilized_state();
            return LoudnessAdjustment {
                short_term_lufs: SILENCE_LUFS,
                gain: 1.0,
                gamma: 1.0,
            };
        }

        self.accumulate_weighted_samples(samples);
        let short_term_lufs = self.short_term_lufs();
        let (gain, gamma) = match mode {
            LufsMode::Manual { gain, gamma } => {
                (sanitize_non_negative(gain), sanitize_gamma(gamma))
            }
            LufsMode::Automatic {
                target_lufs,
                base_gamma,
                max_gamma,
                sigma_lufs,
                smoothing_alpha,
            } => self.stabilized_automatic_adjustment(
                short_term_lufs,
                target_lufs,
                base_gamma,
                max_gamma,
                sigma_lufs,
                smoothing_alpha,
            ),
        };
        LoudnessAdjustment {
            short_term_lufs,
            gain,
            gamma,
        }
    }

    /// RF4.3.3: applies only the slow, bounded global LUFS gain. The hybrid
    /// Pico Maestro owns the common divisor; gamma remains neutral by design.
    pub fn process_hybrid_samples(
        &mut self,
        samples: &[f32],
        mode: LufsMode,
    ) -> LoudnessAdjustment {
        self.accumulate_weighted_samples(samples);
        let short_term_lufs = self.short_term_lufs();
        if short_term_lufs < HYBRID_SILENCE_GATE_LUFS {
            self.reset_stabilized_state();
            return LoudnessAdjustment {
                short_term_lufs: SILENCE_LUFS,
                gain: 1.0,
                gamma: 1.0,
            };
        }

        let gain = match mode {
            // Manual profiles remain useful as diagnostic controls, but the
            // optional hybrid contrast is intentionally fixed at gamma=1.
            LufsMode::Manual { gain, .. } => {
                sanitize_non_negative(gain).clamp(HYBRID_GAIN_MIN, HYBRID_GAIN_MAX)
            }
            LufsMode::Automatic { target_lufs, .. } => {
                self.hybrid_automatic_gain(short_term_lufs, target_lufs)
            }
        };
        LoudnessAdjustment {
            short_term_lufs,
            gain,
            gamma: 1.0,
        }
    }

    /// RF4.3: `Efinal = clamp((E * G)^gamma, 0, 1)` before FFI publication.
    pub fn condition_band_energies(energies: &mut [f32], adjustment: LoudnessAdjustment) {
        for energy in energies {
            let conditioned = sanitize_non_negative(*energy) * adjustment.gain;
            *energy = if conditioned > 0.0 {
                conditioned.powf(adjustment.gamma).clamp(0.0, 1.0)
            } else {
                0.0
            };
        }
    }

    /// RF4.3.2 mode A: the pivot retains its absolute height while gamma
    /// changes contrast above and below it.
    pub fn condition_band_energies_with_pivot(
        energies: &mut [f32],
        adjustment: LoudnessAdjustment,
    ) {
        for energy in energies {
            let input = (sanitize_non_negative(*energy) * adjustment.gain).clamp(0.0, 1.0);
            *energy = if input > 0.0 {
                (STABILIZED_PIVOT * (input / STABILIZED_PIVOT).powf(adjustment.gamma))
                    .clamp(0.0, 1.0)
            } else {
                0.0
            };
        }
    }

    pub fn reset_stabilized_state(&mut self) {
        self.squared_window.clear();
        self.squared_sum = 0.0;
        self.smoothed_gain = 1.0;
        self.smoothed_gamma = 1.0;
        self.stage1 = Biquad::default();
        self.stage2 = Biquad::default();
    }

    fn accumulate_weighted_samples(&mut self, samples: &[f32]) {
        let capacity = self.sample_rate_hz as usize * SHORT_TERM_WINDOW_SECONDS;
        for sample in samples {
            let weighted = self.stage2.process(
                self.stage1.process(
                    *sample,
                    [STAGE1_B0, STAGE1_B1, STAGE1_B2, STAGE1_A1, STAGE1_A2],
                ),
                [STAGE2_B0, STAGE2_B1, STAGE2_B2, STAGE2_A1, STAGE2_A2],
            );
            let square = sanitize_non_negative(weighted * weighted);
            self.squared_window.push_back(square);
            self.squared_sum += f64::from(square);
            if self.squared_window.len() > capacity {
                self.squared_sum -= f64::from(self.squared_window.pop_front().unwrap_or_default());
            }
        }
    }

    fn short_term_lufs(&self) -> f32 {
        if self.squared_window.is_empty() || self.squared_sum <= f64::EPSILON {
            return SILENCE_LUFS;
        }
        (-0.691 + 10.0 * (self.squared_sum / self.squared_window.len() as f64).log10()) as f32
    }

    #[allow(clippy::too_many_arguments)]
    fn automatic_adjustment(
        &mut self,
        short_term_lufs: f32,
        target_lufs: f32,
        base_gamma: f32,
        max_gamma: f32,
        sigma_lufs: f32,
        smoothing_alpha: f32,
    ) -> (f32, f32) {
        let delta_lufs = short_term_lufs - target_lufs;
        let raw_gain = 10.0_f32.powf(-delta_lufs / 20.0).clamp(0.0, 8.0);
        let alpha = smoothing_alpha.clamp(0.01, 0.05);
        self.smoothed_gain += alpha * (raw_gain - self.smoothed_gain);
        self.smoothed_gain = self.smoothed_gain.clamp(0.0, 8.0);
        let base_gamma = sanitize_gamma(base_gamma);
        let max_gamma = sanitize_gamma(max_gamma).max(base_gamma);
        let raw_gamma = (base_gamma
            + (max_gamma - base_gamma) * (delta_lufs / sigma_lufs.abs().max(f32::EPSILON)).tanh())
        .clamp(base_gamma, max_gamma);
        self.smoothed_gamma += alpha * (raw_gamma - self.smoothed_gamma);
        self.smoothed_gamma = self.smoothed_gamma.clamp(base_gamma, max_gamma);
        (self.smoothed_gain, self.smoothed_gamma)
    }

    #[allow(clippy::too_many_arguments)]
    fn stabilized_automatic_adjustment(
        &mut self,
        short_term_lufs: f32,
        target_lufs: f32,
        base_gamma: f32,
        max_gamma: f32,
        sigma_lufs: f32,
        smoothing_alpha: f32,
    ) -> (f32, f32) {
        let delta_lufs = short_term_lufs - target_lufs;
        let raw_gain = 10.0_f32.powf(-delta_lufs / 20.0).clamp(0.0, 8.0);
        let alpha = smoothing_alpha.clamp(0.01, 0.05);
        self.smoothed_gain += alpha * (raw_gain - self.smoothed_gain);
        self.smoothed_gain = self.smoothed_gain.clamp(0.0, 8.0);

        let base_gamma = sanitize_gamma(base_gamma);
        let max_gamma = sanitize_gamma(max_gamma).max(base_gamma);
        let contrast_delta = (delta_lufs - STABILIZED_GAMMA_DEADBAND_LU).max(0.0);
        let raw_gamma = (base_gamma
            + (max_gamma - base_gamma)
                * (contrast_delta / sigma_lufs.abs().max(f32::EPSILON)).tanh())
        .clamp(base_gamma, max_gamma);
        self.smoothed_gamma += alpha * (raw_gamma - self.smoothed_gamma);
        self.smoothed_gamma = self.smoothed_gamma.clamp(base_gamma, max_gamma);
        (self.smoothed_gain, self.smoothed_gamma)
    }

    fn hybrid_automatic_gain(&mut self, short_term_lufs: f32, target_lufs: f32) -> f32 {
        let delta_lufs = short_term_lufs - target_lufs;
        let raw_gain = if delta_lufs.abs() <= HYBRID_GAIN_DEADBAND_LU {
            1.0
        } else {
            10.0_f32
                .powf(-delta_lufs / 20.0)
                .clamp(HYBRID_GAIN_MIN, HYBRID_GAIN_MAX)
        };
        self.smoothed_gain += HYBRID_GAIN_SMOOTHING_ALPHA * (raw_gain - self.smoothed_gain);
        self.smoothed_gain = self.smoothed_gain.clamp(HYBRID_GAIN_MIN, HYBRID_GAIN_MAX);
        self.smoothed_gain
    }
}

fn is_below_stabilized_silence_gate(samples: &[f32]) -> bool {
    if samples.is_empty() {
        return true;
    }
    let mean_square = samples
        .iter()
        .map(|sample| sanitize_sample(*sample).powi(2))
        .sum::<f32>()
        / samples.len() as f32;
    let threshold = 10.0_f32.powf(STABILIZED_SILENCE_GATE_DBFS / 20.0);
    mean_square.sqrt() <= threshold
}

fn sanitize_sample(value: f32) -> f32 {
    if value.is_finite() {
        value
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
fn sanitize_gamma(value: f32) -> f32 {
    if value.is_finite() {
        value.clamp(0.01, 8.0)
    } else {
        1.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn sine_wave(frequency_hz: f32, amplitude: f32, sample_count: usize) -> Vec<f32> {
        (0..sample_count)
            .map(|index| {
                amplitude
                    * (2.0 * std::f32::consts::PI * frequency_hz * index as f32 / 48_000.0).sin()
            })
            .collect()
    }
    #[test]
    fn k_weighting_strongly_rejects_low_frequency_content() {
        let samples = 48_000 * 3;
        let low = LoudnessProcessor::new(48_000)
            .process_samples(&sine_wave(60.0, 0.5, samples), LufsMode::default());
        let mid = LoudnessProcessor::new(48_000)
            .process_samples(&sine_wave(1_000.0, 0.5, samples), LufsMode::default());
        // The RLB stage is specified as a 100 Hz high-pass, so 60 Hz is
        // attenuated substantially but not removed completely.
        assert!(
            mid.short_term_lufs > low.short_term_lufs,
            "expected 1 kHz ({}) to exceed 60 Hz ({}) after K-weighting",
            mid.short_term_lufs,
            low.short_term_lufs
        );
    }
    #[test]
    fn short_term_loudness_integrates_three_seconds_of_audio() {
        let mut processor = LoudnessProcessor::new(48_000);
        let one_second = sine_wave(1_000.0, 0.25, 48_000);
        let first = processor.process_samples(&one_second, LufsMode::default());
        let second = processor.process_samples(&one_second, LufsMode::default());
        let third = processor.process_samples(&one_second, LufsMode::default());
        assert!(third.short_term_lufs.is_finite());
        assert!((second.short_term_lufs - third.short_term_lufs).abs() < 0.1);
        assert!(first.short_term_lufs < 0.0);
    }
    #[test]
    fn automatic_mode_reduces_gain_for_loud_programme_material() {
        let mut processor = LoudnessProcessor::new(48_000);
        let adjustment =
            processor.process_samples(&sine_wave(1_000.0, 1.0, 48_000 * 3), LufsMode::default());
        assert!(adjustment.gain < 1.0);
        assert!(adjustment.gamma >= 1.0);
    }
    #[test]
    fn rf4_3_defaults_match_the_normative_dynamic_conditioning_values() {
        assert_eq!(
            LufsMode::default(),
            LufsMode::Automatic {
                target_lufs: -14.0,
                base_gamma: 1.0,
                max_gamma: 2.2,
                sigma_lufs: 6.0,
                smoothing_alpha: 0.03,
            }
        );
    }
    #[test]
    fn manual_mode_and_output_conditioning_clamp_every_value() {
        let mut processor = LoudnessProcessor::new(48_000);
        let adjustment = processor.process_samples(
            &[0.0; 64],
            LufsMode::Manual {
                gain: 2.0,
                gamma: 2.0,
            },
        );
        assert_eq!(adjustment.gain, 2.0);
        assert_eq!(adjustment.gamma, 2.0);
        let mut energies = [-1.0, 0.5, 2.0, f32::NAN, f32::INFINITY];
        LoudnessProcessor::condition_band_energies(&mut energies, adjustment);
        assert_eq!(energies, [0.0, 1.0, 1.0, 0.0, 0.0]);
    }

    #[test]
    fn rf4_3_2_stabilized_mode_resets_after_silence_and_has_a_gamma_deadband() {
        let mut processor = LoudnessProcessor::new(48_000);
        for _ in 0..20 {
            processor.process_samples(&[0.0; 1_024], LufsMode::default());
        }
        let silence = processor.process_stabilized_samples(&[0.0; 1_024], LufsMode::default());
        assert_eq!(silence.gain, 1.0);
        assert_eq!(silence.gamma, 1.0);

        let near_target =
            processor.stabilized_automatic_adjustment(-13.0, -14.0, 1.0, 2.2, 6.0, 0.03);
        assert_eq!(
            near_target.1, 1.0,
            "within the 1.5 LU deadband gamma is neutral"
        );
    }

    #[test]
    fn rf4_3_2_pivot_preserves_reference_and_increases_only_upper_contrast() {
        let adjustment = LoudnessAdjustment {
            short_term_lufs: -10.0,
            gain: 1.0,
            gamma: 1.5,
        };
        let mut energies = [
            STABILIZED_PIVOT,
            STABILIZED_PIVOT * 2.0,
            STABILIZED_PIVOT * 0.5,
        ];
        LoudnessProcessor::condition_band_energies_with_pivot(&mut energies, adjustment);
        assert!((energies[0] - STABILIZED_PIVOT).abs() < 0.000_001);
        assert!(energies[1] > STABILIZED_PIVOT * 2.0);
        assert!(energies[2] < STABILIZED_PIVOT * 0.5);
    }

    #[test]
    fn rf4_3_3_hybrid_lufs_uses_deadband_limits_and_slow_iir() {
        let mut processor = LoudnessProcessor::new(48_000);
        assert_eq!(processor.hybrid_automatic_gain(-12.0, -14.0), 1.0);
        assert_eq!(processor.hybrid_automatic_gain(-16.0, -14.0), 1.0);

        let low_programme = processor.hybrid_automatic_gain(-40.0, -14.0);
        assert!((low_programme - 1.01).abs() < 0.000_001);
        for _ in 0..2_000 {
            processor.hybrid_automatic_gain(-40.0, -14.0);
        }
        assert!((processor.smoothed_gain - HYBRID_GAIN_MAX).abs() < 0.000_1);

        let silence = processor.process_hybrid_samples(&[0.0; 1_024], LufsMode::default());
        assert_eq!(silence.short_term_lufs, SILENCE_LUFS);
        assert_eq!(silence.gain, 1.0);
        assert_eq!(silence.gamma, 1.0);
    }
}
