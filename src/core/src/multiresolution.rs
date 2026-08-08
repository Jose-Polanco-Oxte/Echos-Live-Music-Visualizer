//! Offline three-resolution HI-FI spectral analysis.

use crate::{
    bands::{generate_band_ranges, integrate_bands_continuous, BandError, BandProfile, BandRange},
    features::{FastFeatures, FeatureExtractor},
    stft::{StftAnalyzer, StftError},
};
use thiserror::Error;

pub const SAMPLE_RATE_HZ: u32 = 48_000;
pub const HOP_FRAMES: usize = 512;
pub const LOW_FFT_SIZE: usize = 4096;
pub const MID_FFT_SIZE: usize = 2048;
pub const HIGH_FFT_SIZE: usize = 1024;

#[derive(Debug, Error)]
pub enum MultiResolutionError {
    #[error(transparent)]
    Stft(#[from] StftError),
    #[error(transparent)]
    Bands(#[from] BandError),
    #[error("each channel must provide a {LOW_FFT_SIZE}-frame history")]
    InvalidHistory,
    #[error("output contains {actual} bands but analyzer was constructed with {expected}")]
    InvalidOutput { expected: usize, actual: usize },
}

#[derive(Debug, Clone, PartialEq)]
pub struct MultiResolutionFrame {
    pub features: FastFeatures,
    pub band_energies: Vec<f32>,
}
impl MultiResolutionFrame {
    pub fn with_band_count(bands: usize) -> Self {
        Self {
            features: FastFeatures::default(),
            band_energies: vec![0.0; bands],
        }
    }
}

pub struct MultiResolutionAnalyzer {
    low: StftAnalyzer,
    mid: StftAnalyzer,
    high: StftAnalyzer,
    ranges: Vec<BandRange>,
    features: FeatureExtractor,
}

impl MultiResolutionAnalyzer {
    pub fn new(profile: BandProfile, band_count: usize) -> Result<Self, MultiResolutionError> {
        Ok(Self {
            low: StftAnalyzer::new(LOW_FFT_SIZE, SAMPLE_RATE_HZ)?,
            mid: StftAnalyzer::new(MID_FFT_SIZE, SAMPLE_RATE_HZ)?,
            high: StftAnalyzer::new(HIGH_FFT_SIZE, SAMPLE_RATE_HZ)?,
            ranges: generate_band_ranges(profile, band_count, 20.0, 20_000.0)?,
            features: FeatureExtractor::new(HIGH_FFT_SIZE / 2 + 1),
        })
    }
    pub fn band_ranges(&self) -> &[BandRange] {
        &self.ranges
    }
    pub fn analyze_into(
        &mut self,
        channels: &[&[f32]],
        output: &mut MultiResolutionFrame,
    ) -> Result<(), MultiResolutionError> {
        if channels.is_empty() || channels.iter().any(|channel| channel.len() != LOW_FFT_SIZE) {
            return Err(MultiResolutionError::InvalidHistory);
        }
        if output.band_energies.len() != self.ranges.len() {
            return Err(MultiResolutionError::InvalidOutput {
                expected: self.ranges.len(),
                actual: output.band_energies.len(),
            });
        }
        self.low.analyze(channels)?;
        // The suffixes are chronological sliding windows over the same history.
        self.mid.analyze_suffixes(channels)?;
        self.high.analyze_suffixes(channels)?;
        integrate_bands_continuous(
            &self.ranges,
            self.low.bin_width_hz(),
            |frequency| self.fused_power_at_hz(frequency),
            &mut output.band_energies,
        )?;
        let rms = FeatureExtractor::rms_from_suffix(channels, HOP_FRAMES);
        output.features = self.features.update(
            self.high.power_spectrum(),
            SAMPLE_RATE_HZ,
            HIGH_FFT_SIZE,
            rms,
        );
        Ok(())
    }
    pub fn fused_power_at_hz(&self, frequency_hz: f32) -> f32 {
        // RF1.4 cross-fades use W_A=cos²(pi*u/2), W_B=1-W_A.
        if frequency_hz <= 200.0 {
            return self.low.power_at_hz(frequency_hz);
        }
        if frequency_hz < 300.0 {
            return blend(
                self.low.power_at_hz(frequency_hz),
                self.mid.power_at_hz(frequency_hz),
                frequency_hz,
                200.0,
                300.0,
            );
        }
        if frequency_hz <= 3800.0 {
            return self.mid.power_at_hz(frequency_hz);
        }
        if frequency_hz < 4200.0 {
            return blend(
                self.mid.power_at_hz(frequency_hz),
                self.high.power_at_hz(frequency_hz),
                frequency_hz,
                3800.0,
                4200.0,
            );
        }
        self.high.power_at_hz(frequency_hz)
    }
}

fn blend(a: f32, b: f32, frequency_hz: f32, low_hz: f32, high_hz: f32) -> f32 {
    let u = ((frequency_hz - low_hz) / (high_hz - low_hz)).clamp(0.0, 1.0);
    let wa = (std::f32::consts::FRAC_PI_2 * u).cos().powi(2);
    wa * a + (1.0 - wa) * b
}

#[cfg(test)]
mod tests {
    use super::*;
    fn tone(frequency_hz: f32) -> Vec<f32> {
        (0..LOW_FFT_SIZE)
            .map(|n| {
                (2.0 * std::f32::consts::PI * frequency_hz * n as f32 / SAMPLE_RATE_HZ as f32).sin()
            })
            .collect()
    }
    #[test]
    fn low_tones_are_resolved_by_4096_not_1024() {
        let mut analyzer = MultiResolutionAnalyzer::new(BandProfile::Erb, 64).unwrap();
        let at_twenty = tone(20.0);
        let at_thirty_one = tone(31.5);
        let mut first = MultiResolutionFrame::with_band_count(64);
        let mut second = MultiResolutionFrame::with_band_count(64);
        analyzer.analyze_into(&[&at_twenty], &mut first).unwrap();
        let twenty_at_twenty = analyzer.fused_power_at_hz(20.0);
        let thirty_one_at_twenty = analyzer.fused_power_at_hz(31.5);
        analyzer
            .analyze_into(&[&at_thirty_one], &mut second)
            .unwrap();
        let twenty_at_thirty_one = analyzer.fused_power_at_hz(20.0);
        let thirty_one_at_thirty_one = analyzer.fused_power_at_hz(31.5);
        assert!(twenty_at_twenty > thirty_one_at_twenty);
        assert!(thirty_one_at_thirty_one > twenty_at_thirty_one);
    }
    #[test]
    fn required_low_frequency_fixture_tones_produce_finite_energy() {
        let mut analyzer = MultiResolutionAnalyzer::new(BandProfile::Erb, 64).unwrap();
        for frequency in [
            20.0, 25.0, 31.5, 40.0, 50.0, 63.0, 80.0, 100.0, 125.0, 160.0, 200.0, 250.0,
        ] {
            let history = tone(frequency);
            let mut frame = MultiResolutionFrame::with_band_count(64);
            analyzer.analyze_into(&[&history], &mut frame).unwrap();
            assert!(frame
                .band_energies
                .iter()
                .all(|x| x.is_finite() && *x >= 0.0));
            assert!(
                frame.band_energies.iter().any(|x| *x > 0.000_001),
                "{frequency} Hz was lost"
            );
        }
    }
    #[test]
    fn crossover_weights_are_continuous_and_complementary() {
        for (start, end) in [(200.0, 300.0), (3800.0, 4200.0)] {
            assert!((blend(1.0, 0.0, start, start, end) - 1.0).abs() < 0.000_001);
            assert!((blend(1.0, 0.0, (start + end) * 0.5, start, end) - 0.5).abs() < 0.000_01);
            assert!(blend(1.0, 0.0, end, start, end) < 0.000_001);
        }
    }

    #[test]
    fn analysis_reuses_the_callers_preallocated_band_output() {
        let history = tone(100.0);
        let mut analyzer = MultiResolutionAnalyzer::new(BandProfile::Erb, 24).unwrap();
        let mut frame = MultiResolutionFrame::with_band_count(24);
        let allocation = frame.band_energies.as_ptr();
        analyzer.analyze_into(&[&history], &mut frame).unwrap();
        analyzer.analyze_into(&[&history], &mut frame).unwrap();
        assert_eq!(allocation, frame.band_energies.as_ptr());
    }
}
