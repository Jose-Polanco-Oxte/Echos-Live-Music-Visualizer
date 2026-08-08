//! Hop-driven DSP scheduling for the ABI v2 pipeline.
//!
//! This module is deliberately polling-safe: it only runs an FFT after it
//! obtains a new [`AudioHop`].  The FFI layer will later retain/read the
//! published [`ScheduledFrame`] without invoking this scheduler.

use std::time::Instant;

use thiserror::Error;

use crate::{
    bands::BandProfile,
    capture::{AudioHop, LoopbackCapture, HOP_FRAMES_PER_CHANNEL, MAX_CAPTURE_CHANNELS},
    MultiResolutionAnalyzer, MultiResolutionError, MultiResolutionFrame, LOW_FFT_SIZE,
};

/// A fully computed frame retained by the scheduler until the next hop.
#[derive(Debug, Clone, PartialEq)]
pub struct ScheduledFrame {
    /// Monotonic sequence number within this generation, beginning at one.
    pub sequence: u64,
    /// Capture timestamp propagated from the source hop.
    pub timestamp_ms: u64,
    /// Generation changed whenever the capture source or analysis profile resets.
    pub generation: u64,
    /// Core compute latency only; it excludes STFT group/window age.
    pub compute_latency_us: u64,
    /// Spectrum and fast features produced once for this hop.
    pub analysis: MultiResolutionFrame,
    pub channels: u8,
}

#[derive(Debug, Error)]
pub enum SchedulerError {
    #[error(transparent)]
    Analysis(#[from] MultiResolutionError),
    #[error("audio hop channel count must be within 1..={MAX_CAPTURE_CHANNELS}, got {0}")]
    InvalidChannelCount(u8),
}

/// Monothread scheduler that keeps a 4096-frame circular history per channel.
///
/// `process_next_hop` is the only bridge to capture and consumes at most one
/// hop. This establishes RF5.1: polling a retained frame cannot schedule DSP.
pub struct DspScheduler {
    analyzer: MultiResolutionAnalyzer,
    history: [[f32; LOW_FFT_SIZE]; MAX_CAPTURE_CHANNELS],
    chronological: [[f32; LOW_FFT_SIZE]; MAX_CAPTURE_CHANNELS],
    write_index: usize,
    active_channels: Option<usize>,
    generation: u64,
    next_sequence: u64,
    analysis_count: u64,
    latest: ScheduledFrame,
    last_hop: AudioHop,
    has_latest: bool,
}

impl DspScheduler {
    pub fn new(profile: BandProfile, band_count: usize) -> Result<Self, SchedulerError> {
        Ok(Self {
            analyzer: MultiResolutionAnalyzer::new(profile, band_count)?,
            history: [[0.0; LOW_FFT_SIZE]; MAX_CAPTURE_CHANNELS],
            chronological: [[0.0; LOW_FFT_SIZE]; MAX_CAPTURE_CHANNELS],
            write_index: 0,
            active_channels: None,
            generation: 0,
            next_sequence: 1,
            analysis_count: 0,
            latest: ScheduledFrame {
                sequence: 0,
                timestamp_ms: 0,
                generation: 0,
                compute_latency_us: 0,
                analysis: MultiResolutionFrame::with_band_count(band_count),
                channels: 0,
            },
            last_hop: AudioHop {
                samples: [[0.0; HOP_FRAMES_PER_CHANNEL]; MAX_CAPTURE_CHANNELS],
                channels: 0,
                timestamp_ms: 0,
            },
            has_latest: false,
        })
    }

    /// Reads at most one ordered hop from WASAPI capture and analyzes it once.
    /// Returns `Ok(false)` if no audio arrived, without performing an FFT.
    pub fn process_next_hop(
        &mut self,
        capture: &mut LoopbackCapture,
    ) -> Result<bool, SchedulerError> {
        let Some(hop) = capture.try_next_hop() else {
            return Ok(false);
        };
        self.process_hop(hop)?;
        Ok(true)
    }

    /// Processes one owned hop. Kept crate-visible for deterministic scheduler
    /// tests and for the future dedicated worker's queue consumer.
    pub(crate) fn process_hop(&mut self, hop: AudioHop) -> Result<(), SchedulerError> {
        let channels = hop.channels as usize;
        if !(1..=MAX_CAPTURE_CHANNELS).contains(&channels) {
            return Err(SchedulerError::InvalidChannelCount(hop.channels));
        }

        // A capture channel-layout change is a distinct audio generation; the
        // old lanes must not leak into the next multichannel power spectrum.
        if self
            .active_channels
            .is_some_and(|active| active != channels)
        {
            self.reset_history();
        }
        self.active_channels = Some(channels);

        self.write_hop(&hop, channels);
        self.copy_chronological_history(channels);

        let started = Instant::now();
        let lane_refs: [&[f32]; MAX_CAPTURE_CHANNELS] =
            std::array::from_fn(|channel| &self.chronological[channel] as &[f32]);
        self.analyzer
            .analyze_into(&lane_refs[..channels], &mut self.latest.analysis)?;
        let compute_latency_us = started.elapsed().as_micros().min(u128::from(u64::MAX)) as u64;

        self.latest.sequence = self.next_sequence;
        self.latest.timestamp_ms = hop.timestamp_ms;
        self.latest.generation = self.generation;
        self.latest.compute_latency_us = compute_latency_us;
        self.latest.channels = hop.channels;
        self.last_hop = hop;
        self.has_latest = true;
        self.next_sequence = self.next_sequence.saturating_add(1);
        self.analysis_count = self.analysis_count.saturating_add(1);
        Ok(())
    }

    /// Starts a fresh device generation while retaining the current profile.
    pub fn reset_for_device(&mut self) {
        self.reset_history();
        self.active_channels = None;
    }

    /// Starts a fresh profile generation and discards all history/onset state.
    pub fn reconfigure(
        &mut self,
        profile: BandProfile,
        band_count: usize,
    ) -> Result<(), SchedulerError> {
        self.analyzer = MultiResolutionAnalyzer::new(profile, band_count)?;
        self.latest.analysis = MultiResolutionFrame::with_band_count(band_count);
        self.reset_for_device();
        Ok(())
    }

    pub fn latest(&self) -> Option<&ScheduledFrame> {
        self.has_latest.then_some(&self.latest)
    }

    pub fn generation(&self) -> u64 {
        self.generation
    }

    pub fn analysis_count(&self) -> u64 {
        self.analysis_count
    }

    pub fn band_centers_hz(&self) -> Vec<f32> {
        self.analyzer
            .band_ranges()
            .iter()
            .map(|range| (range.start_hz * range.end_hz).sqrt())
            .collect()
    }

    pub fn band_ranges_hz(&self) -> Vec<crate::BandRange> {
        self.analyzer
            .band_ranges()
            .iter()
            .map(|range| crate::BandRange {
                start_hz: range.start_hz,
                end_hz: range.end_hz,
            })
            .collect()
    }

    pub fn latest_hop(&self) -> Option<&AudioHop> {
        self.has_latest.then_some(&self.last_hop)
    }

    fn reset_history(&mut self) {
        self.history = [[0.0; LOW_FFT_SIZE]; MAX_CAPTURE_CHANNELS];
        self.chronological = [[0.0; LOW_FFT_SIZE]; MAX_CAPTURE_CHANNELS];
        self.write_index = 0;
        self.has_latest = false;
        self.next_sequence = 1;
        self.generation = self.generation.saturating_add(1);
    }

    fn write_hop(&mut self, hop: &AudioHop, channels: usize) {
        for (channel, lane) in self.history[..channels].iter_mut().enumerate() {
            for (offset, sample) in hop.samples[channel].iter().enumerate() {
                lane[(self.write_index + offset) % LOW_FFT_SIZE] = *sample;
            }
        }
        self.write_index = (self.write_index + HOP_FRAMES_PER_CHANNEL) % LOW_FFT_SIZE;
    }

    fn copy_chronological_history(&mut self, channels: usize) {
        for channel in 0..channels {
            let source = &self.history[channel];
            let target = &mut self.chronological[channel];
            let split = LOW_FFT_SIZE - self.write_index;
            target[..split].copy_from_slice(&source[self.write_index..]);
            target[split..].copy_from_slice(&source[..self.write_index]);
        }
    }

    #[cfg(test)]
    fn chronological_lane(&self, channel: usize) -> &[f32; LOW_FFT_SIZE] {
        &self.chronological[channel]
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn hop(channels: usize, timestamp_ms: u64, base: f32) -> AudioHop {
        let mut hop = AudioHop {
            samples: [[0.0; HOP_FRAMES_PER_CHANNEL]; MAX_CAPTURE_CHANNELS],
            channels: channels as u8,
            timestamp_ms,
        };
        for channel in 0..channels {
            for (index, sample) in hop.samples[channel].iter_mut().enumerate() {
                *sample = base + channel as f32 * 10_000.0 + index as f32;
            }
        }
        hop
    }

    fn scheduler() -> DspScheduler {
        DspScheduler::new(BandProfile::Erb, 12).unwrap()
    }

    #[test]
    fn chronological_window_contains_exact_last_4096_samples() {
        let mut scheduler = scheduler();
        for number in 0..9 {
            scheduler
                .process_hop(hop(1, number, number as f32 * 512.0))
                .unwrap();
        }
        let lane = scheduler.chronological_lane(0);
        assert_eq!(lane[0], 512.0);
        assert_eq!(lane[LOW_FFT_SIZE - 1], 4_607.0);
        assert_eq!(lane[1_023], 1_535.0);
        assert_eq!(lane[1_024], 1_536.0);
    }

    #[test]
    fn retained_reads_do_not_schedule_additional_fft() {
        let mut scheduler = scheduler();
        assert_eq!(scheduler.analysis_count(), 0);
        assert!(scheduler.latest().is_none());
        scheduler.process_hop(hop(1, 10, 0.0)).unwrap();
        let after_hop = scheduler.analysis_count();
        for _ in 0..1_000 {
            let _ = scheduler.latest();
        }
        assert_eq!(scheduler.analysis_count(), after_hop);
    }

    #[test]
    fn sequence_and_timestamp_follow_each_processed_hop() {
        let mut scheduler = scheduler();
        scheduler.process_hop(hop(1, 101, 0.0)).unwrap();
        let first = scheduler.latest().unwrap();
        assert_eq!((first.sequence, first.timestamp_ms), (1, 101));
        scheduler.process_hop(hop(1, 202, 512.0)).unwrap();
        let second = scheduler.latest().unwrap();
        assert_eq!((second.sequence, second.timestamp_ms), (2, 202));
        assert!(second.compute_latency_us < u64::MAX);
    }

    #[test]
    fn resetting_generation_cannot_mix_prior_device_history() {
        let mut scheduler = scheduler();
        scheduler.process_hop(hop(1, 1, 42.0)).unwrap();
        let prior_generation = scheduler.generation();
        scheduler.reset_for_device();
        assert_eq!(scheduler.generation(), prior_generation + 1);
        assert!(scheduler.latest().is_none());
        scheduler.process_hop(hop(1, 2, 7.0)).unwrap();
        let lane = scheduler.chronological_lane(0);
        assert!(lane[..LOW_FFT_SIZE - HOP_FRAMES_PER_CHANNEL]
            .iter()
            .all(|sample| *sample == 0.0));
        assert_eq!(lane[LOW_FFT_SIZE - HOP_FRAMES_PER_CHANNEL], 7.0);
        assert_eq!(scheduler.latest().unwrap().generation, prior_generation + 1);
    }

    #[test]
    fn logical_producer_and_render_read_rates_never_duplicate_processing() {
        for render_hz in [60_u32, 120, 144] {
            let mut scheduler = scheduler();
            let duration_ms = 1_000_u64;
            let mut produced = 0_u64;
            let reads = u64::from(render_hz) * duration_ms / 1_000;
            for read in 0..reads {
                let now_us = read * 1_000_000 / u64::from(render_hz);
                // 93.75 Hz = 32/3 ms per hop, represented as 32_000/3 µs.
                let mut next_hop_us = produced * 32_000 / 3;
                while next_hop_us <= now_us {
                    scheduler
                        .process_hop(hop(1, next_hop_us / 1_000, produced as f32))
                        .unwrap();
                    produced += 1;
                    next_hop_us = produced * 32_000 / 3;
                }
                let _ = scheduler.latest();
            }
            assert_eq!(scheduler.analysis_count(), produced, "{render_hz} Hz reads");
        }
    }
}
