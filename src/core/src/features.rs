//! Fast, per-hop descriptors independent from visual smoothing.

use std::collections::VecDeque;

#[derive(Debug, Clone, Copy, Default, PartialEq)]
pub struct FastFeatures {
    pub rms: f32,
    pub spectral_centroid_hz: f32,
    pub onset_detected: bool,
    pub onset_score: f32,
}

pub struct FeatureExtractor {
    previous_fast_power: Vec<f32>,
    flux_history: VecDeque<f32>,
}

impl FeatureExtractor {
    pub fn new(fast_bins: usize) -> Self {
        Self {
            previous_fast_power: vec![0.0; fast_bins],
            flux_history: VecDeque::with_capacity(30),
        }
    }

    /// RF3.1: RMS is mean channel power, so anti-phase PCM channels cannot cancel.
    pub fn rms_from_hop(channels: &[&[f32]]) -> f32 {
        if channels.is_empty() {
            return 0.0;
        }
        let samples = channels[0].len();
        if samples == 0 || channels.iter().any(|channel| channel.len() != samples) {
            return 0.0;
        }
        let total: f32 = channels
            .iter()
            .flat_map(|channel| channel.iter())
            .map(|sample| {
                if sample.is_finite() {
                    sample * sample
                } else {
                    0.0
                }
            })
            .sum();
        (total / (channels.len() * samples) as f32).sqrt()
    }

    pub fn rms_from_suffix(channels: &[&[f32]], frames: usize) -> f32 {
        if channels.is_empty()
            || frames == 0
            || channels.iter().any(|channel| channel.len() < frames)
        {
            return 0.0;
        }
        let total: f32 = channels
            .iter()
            .flat_map(|channel| channel[channel.len() - frames..].iter())
            .map(|sample| {
                if sample.is_finite() {
                    sample * sample
                } else {
                    0.0
                }
            })
            .sum();
        (total / (channels.len() * frames) as f32).sqrt()
    }

    pub fn update(
        &mut self,
        fast_power: &[f32],
        sample_rate_hz: u32,
        fft_size: usize,
        rms: f32,
    ) -> FastFeatures {
        let mut power_sum = 0.0;
        let mut weighted_frequency = 0.0;
        let mut flux = 0.0;
        for (index, (&current, previous)) in fast_power
            .iter()
            .zip(&mut self.previous_fast_power)
            .enumerate()
        {
            let current = current.max(0.0);
            power_sum += current;
            weighted_frequency += index as f32 * sample_rate_hz as f32 / fft_size as f32 * current;
            flux += (current - *previous).max(0.0);
            *previous = current;
        }
        let (mean, stddev) = if self.flux_history.len() >= 3 {
            let mean = self.flux_history.iter().sum::<f32>() / self.flux_history.len() as f32;
            let variance = self
                .flux_history
                .iter()
                .map(|value| (value - mean).powi(2))
                .sum::<f32>()
                / self.flux_history.len() as f32;
            (mean, variance.sqrt())
        } else {
            (0.0, 0.0)
        };
        let excess = (flux - mean - 1.5 * stddev).max(0.0);
        let onset = self.flux_history.len() >= 3 && excess > 0.000_001;
        if self.flux_history.len() == 30 {
            self.flux_history.pop_front();
        }
        self.flux_history.push_back(flux);
        FastFeatures {
            rms,
            spectral_centroid_hz: if power_sum > f32::EPSILON {
                weighted_frequency / power_sum
            } else {
                0.0
            },
            onset_detected: onset,
            onset_score: (excess / (mean + stddev + 0.000_001)).clamp(0.0, 1.0),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn rms_does_not_cancel_antiphase_channels() {
        let left = [1.0; 512];
        let right = [-1.0; 512];
        assert!((FeatureExtractor::rms_from_hop(&[&left, &right]) - 1.0).abs() < 0.000_01);
    }

    #[test]
    fn onset_is_emitted_once_for_the_fast_transient_hop() {
        let mut features = FeatureExtractor::new(4);
        for _ in 0..3 {
            assert!(!features.update(&[0.0; 4], 48_000, 1024, 0.0).onset_detected);
        }
        assert!(
            features
                .update(&[0.0, 1.0, 0.0, 0.0], 48_000, 1024, 0.5)
                .onset_detected
        );
        assert!(
            !features
                .update(&[0.0, 1.0, 0.0, 0.0], 48_000, 1024, 0.5)
                .onset_detected
        );
    }
}
