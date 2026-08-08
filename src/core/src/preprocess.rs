use std::collections::VecDeque;

use rubato::{
    Resampler, SincFixedIn, SincInterpolationParameters, SincInterpolationType, WindowFunction,
};
use thiserror::Error;

/// The common rate used by the STFT and K-weighting stages.
pub const TARGET_SAMPLE_RATE_HZ: u32 = 48_000;
const RESAMPLER_INPUT_FRAMES: usize = 512;

#[derive(Debug, Error, PartialEq, Eq)]
pub enum PreprocessError {
    #[error("the input sample rate must be greater than zero")]
    ZeroSampleRate,
    #[error("the channel count must be greater than zero")]
    ZeroChannelCount,
    #[error("unsupported PCM sample rate {0}; expected 44.1, 48 or 96 kHz")]
    UnsupportedSampleRate(u32),
    #[error("interleaved PCM length {sample_count} is not divisible by {channels} channels")]
    IncompleteInterleavedFrame {
        sample_count: usize,
        channels: usize,
    },
    #[error("rubato FIR resampler could not process PCM")]
    Resampling,
}

/// RF1.1 channel-preserving, stateful rubato FIR/polyphase conversion.
///
/// Downmixing here would erase anti-phase material before the FFT.  The caller
/// receives one continuous 48 kHz lane per source channel and may combine
/// powers only after analysis (RF1.1 / RF1.2).
pub struct ChannelPreprocessor {
    input_sample_rate_hz: u32,
    channels: usize,
    pending: Vec<VecDeque<f32>>,
    input_chunk: Vec<Vec<f32>>,
    resample_output: Vec<Vec<f32>>,
    resampler: Option<SincFixedIn<f32>>,
}

impl ChannelPreprocessor {
    pub fn new(input_sample_rate_hz: u32, channels: usize) -> Result<Self, PreprocessError> {
        validate_format(input_sample_rate_hz, channels)?;
        let resampler = (input_sample_rate_hz != TARGET_SAMPLE_RATE_HZ)
            .then(|| new_resampler(input_sample_rate_hz, channels))
            .transpose()?;
        let resample_output = resampler.as_ref().map_or_else(
            || (0..channels).map(|_| Vec::new()).collect(),
            |value| value.output_buffer_allocate(true),
        );
        Ok(Self {
            input_sample_rate_hz,
            channels,
            pending: (0..channels)
                .map(|_| VecDeque::with_capacity(RESAMPLER_INPUT_FRAMES * 2))
                .collect(),
            input_chunk: (0..channels)
                .map(|_| Vec::with_capacity(RESAMPLER_INPUT_FRAMES))
                .collect(),
            resample_output,
            resampler,
        })
    }

    pub fn channels(&self) -> usize {
        self.channels
    }
    pub fn input_sample_rate_hz(&self) -> u32 {
        self.input_sample_rate_hz
    }

    /// Appends output to preallocated per-channel vectors. Partial source
    /// callbacks are retained, so packet boundaries cannot drop, duplicate or
    /// reorder samples.
    pub fn process_interleaved(
        &mut self,
        interleaved_pcm: &[f32],
        output: &mut [Vec<f32>],
    ) -> Result<(), PreprocessError> {
        if output.len() != self.channels || !interleaved_pcm.len().is_multiple_of(self.channels) {
            return Err(PreprocessError::IncompleteInterleavedFrame {
                sample_count: interleaved_pcm.len(),
                channels: self.channels,
            });
        }
        output.iter_mut().for_each(Vec::clear);
        if self.resampler.is_none() {
            for frame in interleaved_pcm.chunks_exact(self.channels) {
                for (lane, sample) in output.iter_mut().zip(frame) {
                    lane.push(sanitize_sample(*sample));
                }
            }
            return Ok(());
        }
        for frame in interleaved_pcm.chunks_exact(self.channels) {
            for (pending, sample) in self.pending.iter_mut().zip(frame) {
                pending.push_back(sanitize_sample(*sample));
            }
        }
        while self.pending[0].len() >= RESAMPLER_INPUT_FRAMES {
            for (chunk, pending) in self.input_chunk.iter_mut().zip(&mut self.pending) {
                chunk.clear();
                chunk.extend(pending.drain(..RESAMPLER_INPUT_FRAMES));
            }
            let (_, produced) = self
                .resampler
                .as_mut()
                .expect("checked above")
                .process_into_buffer(&self.input_chunk, &mut self.resample_output, None)
                .map_err(|_| PreprocessError::Resampling)?;
            for (destination, source) in output.iter_mut().zip(&self.resample_output) {
                destination.extend(source[..produced].iter().copied().map(sanitize_sample));
            }
        }
        Ok(())
    }
}

fn validate_format(input_sample_rate_hz: u32, channels: usize) -> Result<(), PreprocessError> {
    if input_sample_rate_hz == 0 {
        return Err(PreprocessError::ZeroSampleRate);
    }
    if channels == 0 {
        return Err(PreprocessError::ZeroChannelCount);
    }
    if !matches!(input_sample_rate_hz, 44_100 | 48_000 | 96_000) {
        return Err(PreprocessError::UnsupportedSampleRate(input_sample_rate_hz));
    }
    Ok(())
}

fn new_resampler(rate: u32, channels: usize) -> Result<SincFixedIn<f32>, PreprocessError> {
    let parameters = SincInterpolationParameters {
        sinc_len: 256,
        f_cutoff: 0.95,
        interpolation: SincInterpolationType::Cubic,
        oversampling_factor: 256,
        window: WindowFunction::BlackmanHarris2,
    };
    SincFixedIn::new(
        TARGET_SAMPLE_RATE_HZ as f64 / rate as f64,
        1.0,
        parameters,
        RESAMPLER_INPUT_FRAMES,
        channels,
    )
    .map_err(|_| PreprocessError::Resampling)
}

/// Compatibility façade for the legacy mono FFI path. New capture code must
/// use `ChannelPreprocessor`; this type downmixes only after every channel has
/// been independently resampled.
pub struct AudioPreprocessor {
    inner: ChannelPreprocessor,
    lanes: Vec<Vec<f32>>,
}

impl AudioPreprocessor {
    pub fn new(rate: u32, channels: usize) -> Result<Self, PreprocessError> {
        Ok(Self {
            inner: ChannelPreprocessor::new(rate, channels)?,
            lanes: (0..channels).map(|_| Vec::new()).collect(),
        })
    }
    pub fn input_sample_rate_hz(&self) -> u32 {
        self.inner.input_sample_rate_hz()
    }
    pub fn channels(&self) -> usize {
        self.inner.channels()
    }
    pub fn process_interleaved(
        &mut self,
        pcm: &[f32],
        output: &mut Vec<f32>,
    ) -> Result<(), PreprocessError> {
        self.inner.process_interleaved(pcm, &mut self.lanes)?;
        output.clear();
        if let Some(first) = self.lanes.first() {
            output.reserve(first.len());
            for sample_index in 0..first.len() {
                output.push(
                    self.lanes
                        .iter()
                        .map(|lane| lane[sample_index])
                        .sum::<f32>()
                        / self.lanes.len() as f32,
                );
            }
        }
        Ok(())
    }
    pub fn inject_silence(output: &mut Vec<f32>, sample_count: usize) {
        output.clear();
        output.resize(sample_count, 0.0);
    }
}

fn sanitize_sample(sample: f32) -> f32 {
    if sample.is_finite() {
        sample
    } else {
        0.0
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn preserves_antiphase_channels_until_after_analysis() {
        let mut processor = ChannelPreprocessor::new(TARGET_SAMPLE_RATE_HZ, 2).unwrap();
        let mut output = vec![Vec::new(), Vec::new()];
        processor
            .process_interleaved(&[0.25, -0.25, 0.5, -0.5], &mut output)
            .unwrap();
        assert_eq!(output[0], [0.25, 0.5]);
        assert_eq!(output[1], [-0.25, -0.5]);
    }

    #[test]
    fn irregular_48k_packets_reconstruct_exact_order_without_nan() {
        let mut processor = ChannelPreprocessor::new(TARGET_SAMPLE_RATE_HZ, 2).unwrap();
        let input: Vec<f32> = (0..997).flat_map(|n| [n as f32, -(n as f32)]).collect();
        let mut received = [Vec::new(), Vec::new()];
        // WASAPI packet boundaries may be irregular, but a PCM packet is still
        // frame-aligned.  The fixture uses 37 stereo frames per callback.
        for packet in input.chunks(74) {
            let usable = packet.len();
            let mut output = vec![Vec::new(), Vec::new()];
            processor
                .process_interleaved(&packet[..usable], &mut output)
                .unwrap();
            received[0].extend_from_slice(&output[0]);
            received[1].extend_from_slice(&output[1]);
        }
        assert_eq!(received[0], (0..997).map(|n| n as f32).collect::<Vec<_>>());
        assert_eq!(
            received[1],
            (0..997).map(|n| -(n as f32)).collect::<Vec<_>>()
        );
        assert!(received.iter().flatten().all(|x| x.is_finite()));
    }

    #[test]
    fn resamples_supported_rates_per_channel_with_continuous_state() {
        for rate in [44_100, 48_000, 96_000] {
            let mut processor = ChannelPreprocessor::new(rate, 2).unwrap();
            let input: Vec<f32> = (0..rate)
                .flat_map(|n| [(n as f32 * 0.01).sin(), -(n as f32 * 0.01).sin()])
                .collect();
            let mut total = 0;
            for packet in input.chunks(2 * 317) {
                let mut output = vec![Vec::new(), Vec::new()];
                processor.process_interleaved(packet, &mut output).unwrap();
                assert_eq!(output[0].len(), output[1].len());
                assert!(output.iter().flatten().all(|x| x.is_finite()));
                total += output[0].len();
            }
            assert!(
                (total as isize - 48_000).abs() < 600,
                "rate={rate}, total={total}"
            );
        }
    }
}
