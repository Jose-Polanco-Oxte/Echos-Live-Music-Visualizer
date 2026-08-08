//! Perceptual band layouts and allocation-free continuous power integration.

use thiserror::Error;

pub const MIN_FREQUENCY_HZ: f32 = 20.0;
pub const MAX_FREQUENCY_HZ: f32 = 20_000.0;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BandProfile {
    Erb,
    LogOctaveThird,
    LogOctaveSixth,
}

#[derive(Debug, Clone, Copy, PartialEq)]
pub struct BandRange {
    pub start_hz: f32,
    pub end_hz: f32,
}

#[derive(Debug, Error, PartialEq, Eq)]
pub enum BandError {
    #[error("band count must be positive")]
    ZeroBandCount,
    #[error("frequency range must be finite, ordered and within 20 Hz–20 kHz")]
    InvalidFrequencyRange,
    #[error("output contains {actual} slots but {expected} bands were requested")]
    InvalidOutputLength { expected: usize, actual: usize },
}

pub fn erb_rate(frequency_hz: f32) -> f32 {
    21.4 * (1.0 + 0.00437 * frequency_hz).log10()
}
fn erb_to_hz(rate: f32) -> f32 {
    (10.0_f32.powf(rate / 21.4) - 1.0) / 0.00437
}

pub fn generate_band_ranges(
    profile: BandProfile,
    count: usize,
    min_hz: f32,
    max_hz: f32,
) -> Result<Vec<BandRange>, BandError> {
    if count == 0 {
        return Err(BandError::ZeroBandCount);
    }
    if !min_hz.is_finite()
        || !max_hz.is_finite()
        || min_hz < MIN_FREQUENCY_HZ
        || max_hz > MAX_FREQUENCY_HZ
        || min_hz >= max_hz
    {
        return Err(BandError::InvalidFrequencyRange);
    }
    let (start, end) = match profile {
        BandProfile::Erb => (erb_rate(min_hz), erb_rate(max_hz)),
        BandProfile::LogOctaveThird | BandProfile::LogOctaveSixth => (min_hz.ln(), max_hz.ln()),
    };
    Ok((0..count)
        .map(|index| {
            let edge = |i: usize| {
                let value = start + (end - start) * i as f32 / count as f32;
                match profile {
                    BandProfile::Erb => erb_to_hz(value),
                    _ => value.exp(),
                }
            };
            BandRange {
                start_hz: edge(index),
                end_hz: edge(index + 1),
            }
        })
        .collect())
}

/// Produces standard fractional-octave layouts when the caller does not supply
/// a target band count. Third- and sixth-octave profiles use exactly their
/// named density; ERB remains a caller-counted perceptual layout.
pub fn generate_fractional_octave_ranges(
    profile: BandProfile,
    min_hz: f32,
    max_hz: f32,
) -> Result<Vec<BandRange>, BandError> {
    let divisions = match profile {
        BandProfile::LogOctaveThird => 3,
        BandProfile::LogOctaveSixth => 6,
        BandProfile::Erb => return Err(BandError::InvalidFrequencyRange),
    };
    if !min_hz.is_finite()
        || !max_hz.is_finite()
        || min_hz < MIN_FREQUENCY_HZ
        || max_hz > MAX_FREQUENCY_HZ
        || min_hz >= max_hz
    {
        return Err(BandError::InvalidFrequencyRange);
    }
    let count = ((max_hz / min_hz).log2() * divisions as f32).ceil() as usize;
    generate_band_ranges(profile, count, min_hz, max_hz)
}

/// Integrates a continuous power sampler using trapezoidal quadrature. The
/// caller provides a preallocated destination; narrow bands get at least three
/// samples and therefore cannot be empty merely for lacking an FFT bin centre.
pub fn integrate_bands_continuous<F>(
    ranges: &[BandRange],
    bin_width_hz: f32,
    mut sample_power: F,
    output: &mut [f32],
) -> Result<(), BandError>
where
    F: FnMut(f32) -> f32,
{
    if output.len() != ranges.len() {
        return Err(BandError::InvalidOutputLength {
            expected: ranges.len(),
            actual: output.len(),
        });
    }
    for (range, energy) in ranges.iter().zip(output) {
        let intervals = ((range.end_hz - range.start_hz) / bin_width_hz)
            .ceil()
            .max(2.0) as usize;
        let step = (range.end_hz - range.start_hz) / intervals as f32;
        let mut sum = 0.0;
        for index in 0..=intervals {
            let weight = if index == 0 || index == intervals {
                0.5
            } else {
                1.0
            };
            sum += weight * sample_power(range.start_hz + index as f32 * step).max(0.0);
        }
        *energy = (sum / intervals as f32).max(0.0);
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn profiles_are_monotonic_contiguous_and_cover_audible_range() {
        for profile in [
            BandProfile::Erb,
            BandProfile::LogOctaveThird,
            BandProfile::LogOctaveSixth,
        ] {
            let ranges = generate_band_ranges(profile, 48, 20.0, 20_000.0).unwrap();
            assert_eq!(ranges.len(), 48);
            assert!((ranges[0].start_hz - 20.0).abs() < 0.001);
            assert!((ranges.last().unwrap().end_hz - 20_000.0).abs() < 0.01);
            assert!(ranges
                .windows(2)
                .all(|pair| pair[0].end_hz <= pair[1].start_hz + 0.001
                    && pair[0].start_hz < pair[0].end_hz));
        }
    }
    #[test]
    fn continuous_integration_keeps_narrow_bands_nonempty_for_non_silent_spectrum() {
        let ranges = generate_band_ranges(BandProfile::Erb, 96, 20.0, 20_000.0).unwrap();
        let mut output = vec![0.0; ranges.len()];
        integrate_bands_continuous(&ranges, 46.875, |_| 1.0, &mut output).unwrap();
        assert!(output.iter().all(|energy| *energy > 0.99));
    }

    #[test]
    fn fractional_octave_profiles_have_their_declared_density() {
        let thirds =
            generate_fractional_octave_ranges(BandProfile::LogOctaveThird, 20.0, 20_000.0).unwrap();
        let sixths =
            generate_fractional_octave_ranges(BandProfile::LogOctaveSixth, 20.0, 20_000.0).unwrap();
        assert_eq!(sixths.len(), thirds.len() * 2);
    }
}
