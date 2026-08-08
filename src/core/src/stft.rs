//! Preallocated single-resolution STFT primitives for the HI-FI pipeline.

use std::sync::Arc;

use rustfft::{num_complex::Complex32, Fft, FftPlanner};
use thiserror::Error;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum StftError {
    #[error("FFT size {0} must be a power of two greater than one")]
    InvalidFftSize(usize),
    #[error(
        "expected every channel to contain {expected} samples, channel {channel} contains {actual}"
    )]
    InvalidChannelLength {
        expected: usize,
        channel: usize,
        actual: usize,
    },
    #[error("at least one channel is required")]
    NoChannels,
}

/// A one-sided, power-normalized STFT. Working storage is allocated only by
/// [`StftAnalyzer::new`]; [`StftAnalyzer::analyze`] reuses it for every channel.
pub struct StftAnalyzer {
    fft_size: usize,
    sample_rate_hz: u32,
    window: Vec<f32>,
    fft: Arc<dyn Fft<f32>>,
    fft_buffer: Vec<Complex32>,
    power: Vec<f32>,
    power_scale: f32,
}

impl StftAnalyzer {
    pub fn new(fft_size: usize, sample_rate_hz: u32) -> Result<Self, StftError> {
        if fft_size <= 1 || !fft_size.is_power_of_two() {
            return Err(StftError::InvalidFftSize(fft_size));
        }
        let window = blackman_harris_4(fft_size);
        let coherent_gain = window.iter().sum::<f32>() / fft_size as f32;
        let mut planner = FftPlanner::<f32>::new();
        Ok(Self {
            fft_size,
            sample_rate_hz,
            window,
            fft: planner.plan_fft_forward(fft_size),
            fft_buffer: vec![Complex32::default(); fft_size],
            power: vec![0.0; fft_size / 2 + 1],
            // RF1.2: retain |X|² semantics while removing window/FFT gain.
            power_scale: 1.0 / (fft_size as f32 * coherent_gain).powi(2),
        })
    }

    pub fn fft_size(&self) -> usize {
        self.fft_size
    }
    pub fn sample_rate_hz(&self) -> u32 {
        self.sample_rate_hz
    }
    pub fn bin_width_hz(&self) -> f32 {
        self.sample_rate_hz as f32 / self.fft_size as f32
    }
    pub fn power_spectrum(&self) -> &[f32] {
        &self.power
    }

    /// RF1.2: computes every channel independently, then combines power:
    /// `P[k] = sum_c |X_c[k]|² / C`. PCM is never downmixed before the FFT.
    pub fn analyze(&mut self, channels: &[&[f32]]) -> Result<(), StftError> {
        self.analyze_windows(channels, 0)
    }

    /// Uses the final `fft_size` samples of each larger chronological history.
    /// This avoids assembling per-resolution channel vectors on the hot path.
    pub fn analyze_suffixes(&mut self, channels: &[&[f32]]) -> Result<(), StftError> {
        self.analyze_windows(channels, 1)
    }

    fn analyze_windows(
        &mut self,
        channels: &[&[f32]],
        allow_suffix: usize,
    ) -> Result<(), StftError> {
        if channels.is_empty() {
            return Err(StftError::NoChannels);
        }
        for (channel, samples) in channels.iter().enumerate() {
            if (allow_suffix == 0 && samples.len() != self.fft_size)
                || (allow_suffix != 0 && samples.len() < self.fft_size)
            {
                return Err(StftError::InvalidChannelLength {
                    expected: self.fft_size,
                    channel,
                    actual: samples.len(),
                });
            }
        }
        self.power.fill(0.0);
        for samples in channels {
            let samples = if allow_suffix == 0 {
                *samples
            } else {
                &samples[samples.len() - self.fft_size..]
            };
            for ((target, window), sample) in self
                .fft_buffer
                .iter_mut()
                .zip(&self.window)
                .zip(samples.iter())
            {
                let s = if sample.is_nan() { 0.0 } else { *sample };
                *target = Complex32::new(s * window, 0.0);
            }
            self.fft.process(&mut self.fft_buffer);
            for (accumulated, coefficient) in self.power.iter_mut().zip(&self.fft_buffer) {
                *accumulated += coefficient.norm_sqr() * self.power_scale;
            }
        }
        let inverse_channels = 1.0 / channels.len() as f32;
        for value in &mut self.power {
            *value *= inverse_channels;
        }
        Ok(())
    }

    pub fn power_at_hz(&self, frequency_hz: f32) -> f32 {
        interpolate_power(&self.power, frequency_hz / self.bin_width_hz())
    }
}

/// RF1.2 four-term Blackman-Harris window.
pub fn blackman_harris_4(size: usize) -> Vec<f32> {
    (0..size)
        .map(|n| {
            let phase = 2.0 * std::f32::consts::PI * n as f32 / (size - 1) as f32;
            0.35875 - 0.48829 * phase.cos() + 0.14128 * (2.0 * phase).cos()
                - 0.01168 * (3.0 * phase).cos()
        })
        .collect()
}

pub fn interpolate_power(power: &[f32], fractional_bin: f32) -> f32 {
    if power.is_empty() || !fractional_bin.is_finite() {
        return 0.0;
    }
    let lower = fractional_bin.floor().max(0.0) as usize;
    let lower = lower.min(power.len() - 1);
    let upper = (lower + 1).min(power.len() - 1);
    let fraction = (fractional_bin - lower as f32).clamp(0.0, 1.0);
    (power[lower] * (1.0 - fraction) + power[upper] * fraction).max(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use approx::assert_abs_diff_eq;

    fn tone(size: usize, frequency_hz: f32) -> Vec<f32> {
        (0..size)
            .map(|n| (2.0 * std::f32::consts::PI * frequency_hz * n as f32 / 48_000.0).sin())
            .collect()
    }

    #[test]
    fn pure_tones_land_at_their_bins_for_all_required_sizes() {
        for size in [1024, 2048, 4096] {
            let bin = 17usize;
            let frequency = bin as f32 * 48_000.0 / size as f32;
            let samples = tone(size, frequency);
            let mut analyzer = StftAnalyzer::new(size, 48_000).unwrap();
            analyzer.analyze(&[&samples]).unwrap();
            let strongest = analyzer
                .power_spectrum()
                .iter()
                .enumerate()
                .max_by(|a, b| a.1.total_cmp(b.1))
                .unwrap()
                .0;
            assert_eq!(strongest, bin);
            assert_abs_diff_eq!(analyzer.power_spectrum()[bin], 0.25, epsilon = 0.002);
        }
    }

    #[test]
    fn anti_phase_channels_keep_power_after_per_channel_fft() {
        let left = tone(1024, 187.5);
        let right: Vec<_> = left.iter().map(|value| -*value).collect();
        let mut analyzer = StftAnalyzer::new(1024, 48_000).unwrap();
        analyzer.analyze(&[&left, &right]).unwrap();
        assert!(analyzer.power_spectrum()[4] > 0.24);
    }

    #[test]
    fn blackman_harris_has_lower_distant_leakage_than_rectangular_and_hamming() {
        let size = 1024;
        let samples = tone(size, 1_013.0);
        let leakage = |window: Vec<f32>| {
            let mut values: Vec<_> = samples
                .iter()
                .zip(window)
                .map(|(x, w)| Complex32::new(x * w, 0.0))
                .collect();
            FftPlanner::<f32>::new()
                .plan_fft_forward(size)
                .process(&mut values);
            let peak = values[..=size / 2]
                .iter()
                .enumerate()
                .max_by(|a, b| a.1.norm().total_cmp(&b.1.norm()))
                .unwrap()
                .0;
            values[..=size / 2]
                .iter()
                .enumerate()
                .filter(|(i, _)| i.abs_diff(peak) > 5)
                .map(|(_, x)| x.norm())
                .fold(0.0, f32::max)
        };
        let bh = leakage(blackman_harris_4(size));
        let rectangular = leakage(vec![1.0; size]);
        let hamming = leakage(
            (0..size)
                .map(|n| {
                    0.54 - 0.46 * (2.0 * std::f32::consts::PI * n as f32 / (size - 1) as f32).cos()
                })
                .collect(),
        );
        assert!(
            bh < rectangular && bh < hamming,
            "BH={bh}, rectangular={rectangular}, hamming={hamming}"
        );
    }
}
