//! WASAPI loopback and direct-input capture isolated from the UI and FFI threads.
//!
//! The callback-facing side only publishes complete, mono 48 kHz blocks. COM
//! objects remain on the dedicated MTA thread because the WASAPI crate marks
//! them as non-Send.

use std::{
    collections::VecDeque,
    sync::mpsc,
    sync::{
        atomic::{AtomicBool, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::Instant,
};

use ringbuf::traits::{Consumer, Observer, Producer};
use wasapi::{
    deinitialize, initialize_mta, DeviceEnumerator, Direction, SampleType, StreamMode, WaveFormat,
};

use crate::preprocess::ChannelPreprocessor;
use crate::spsc::{CaptureTelemetry, CaptureTelemetrySnapshot};
use crate::{create_spsc_queue, AudioPreprocessor, PreprocessError, SpscConsumer, SpscProducer};

const TARGET_SAMPLE_RATE: usize = 48_000;
const DEFAULT_CAPTURE_CHANNELS: usize = 2;
const MIN_CAPTURE_FRAME_SIZE: usize = 512;
const MAX_CAPTURE_FRAME_SIZE: usize = 1_024;
pub const HOP_FRAMES_PER_CHANNEL: usize = 512;
pub const MAX_CAPTURE_CHANNELS: usize = 8;
const HOP_QUEUE_CAPACITY: usize = 32;

/// RF1.1 fixed-size multichannel quantum. `samples[channel][frame]` is stored
/// inline in the SPSC ring: pushing and consuming a hop performs no heap
/// allocation and the receiver owns the hop without cloning it.
#[derive(Clone)]
pub struct AudioHop {
    pub samples: [[f32; HOP_FRAMES_PER_CHANNEL]; MAX_CAPTURE_CHANNELS],
    pub channels: u8,
    pub timestamp_ms: u64,
}

impl AudioHop {
    fn empty(channels: usize, timestamp_ms: u64) -> Self {
        Self {
            samples: [[0.0; HOP_FRAMES_PER_CHANNEL]; MAX_CAPTURE_CHANNELS],
            channels: channels as u8,
            timestamp_ms,
        }
    }

    #[allow(dead_code)] // used by the next scheduler crate-local consumer.
    pub fn channel(&self, channel: usize) -> Option<&[f32; HOP_FRAMES_PER_CHANNEL]> {
        (channel < self.channels as usize).then(|| &self.samples[channel])
    }
}

/// Collects irregular normalized callback packets into exact 512-frame hops.
/// The queues are allocated once at construction; `push_lanes` only writes
/// existing storage and invokes the non-blocking publisher.
struct HopAssembler {
    channels: usize,
    lanes: Vec<VecDeque<f32>>,
}

impl HopAssembler {
    fn new(channels: usize) -> Result<Self, String> {
        if !(1..=MAX_CAPTURE_CHANNELS).contains(&channels) {
            return Err("capture channel count must be within 1..=8".to_owned());
        }
        Ok(Self {
            channels,
            lanes: (0..channels)
                .map(|_| VecDeque::with_capacity(HOP_FRAMES_PER_CHANNEL * 2))
                .collect(),
        })
    }

    fn push_lanes(
        &mut self,
        lanes: &[Vec<f32>],
        timestamp_ms: u64,
        mut publish: impl FnMut(AudioHop),
    ) {
        debug_assert_eq!(lanes.len(), self.channels);
        for (pending, source) in self.lanes.iter_mut().zip(lanes) {
            pending.extend(source.iter().copied());
        }
        while self.lanes[0].len() >= HOP_FRAMES_PER_CHANNEL {
            let mut hop = AudioHop::empty(self.channels, timestamp_ms);
            for (channel, pending) in self.lanes.iter_mut().enumerate() {
                for sample in &mut hop.samples[channel] {
                    *sample = pending.pop_front().expect("all channel lanes are aligned");
                }
            }
            publish(hop);
        }
    }
}

/// Latest complete PCM block captured from the Windows render endpoint.
/// The consumer takes a copy deliberately: it never observes a half-written
/// audio block and the 1024-sample allocation is outside the render path.
#[derive(Clone, Default)]
pub struct CapturedBlock {
    pub samples: Vec<f32>,
    pub timestamp_ms: u64,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum AudioDeviceKind {
    /// A render endpoint used with WASAPI's loopback stream flag.
    LoopbackRender,
    /// A capture endpoint such as a microphone, line-in or virtual input.
    DirectCapture,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct AudioDevice {
    pub id: String,
    pub name: String,
    pub is_default: bool,
    kind: AudioDeviceKind,
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum CaptureSource {
    DefaultLoopback,
    RenderLoopback(String),
    DirectInput(String),
}

pub struct LoopbackCapture {
    consumer: SpscConsumer<CapturedBlock>,
    #[allow(dead_code)] // consumed by ABI v2 scheduler in the next block.
    hop_consumer: SpscConsumer<AudioHop>,
    last: CapturedBlock,
    telemetry: Arc<CaptureTelemetry>,
    stop_requested: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

impl LoopbackCapture {
    pub fn start(frame_size: usize, device_id: Option<String>) -> Result<Self, String> {
        // RF1.1: PCM analysis frames are powers of two in the inclusive 512–1024 range.
        validate_capture_frame_size(frame_size)?;
        let source = match device_id {
            Some(id) => capture_source_for_device_id(&id)?,
            None => CaptureSource::DefaultLoopback,
        };

        let last = CapturedBlock {
            samples: vec![0.0; frame_size],
            timestamp_ms: 0,
        };
        // RF1.1: 32 x 512-frame hops provides 16,384 frames of continuous
        // SPSC capacity. The legacy FFI consumer still reads 512/1024 mono
        // blocks until ABI v2 takes ownership of per-channel hops.
        let (producer, consumer) = create_spsc_queue(HOP_QUEUE_CAPACITY);
        let (hop_producer, hop_consumer) = create_spsc_queue(HOP_QUEUE_CAPACITY);
        let stop_requested = Arc::new(AtomicBool::new(false));
        let worker_stop = Arc::clone(&stop_requested);
        let telemetry = CaptureTelemetry::shared();
        let worker_telemetry = Arc::clone(&telemetry);
        let thread = thread::Builder::new()
            .name("echo-wasapi-loopback".to_owned())
            .spawn(move || {
                capture_loop(
                    producer,
                    hop_producer,
                    worker_stop,
                    frame_size,
                    source,
                    worker_telemetry,
                )
            })
            .map_err(|error| format!("could not start WASAPI capture thread: {error}"))?;

        Ok(Self {
            consumer,
            hop_consumer,
            last,
            telemetry,
            stop_requested,
            thread: Some(thread),
        })
    }

    /// Returns the most recent complete block and whether the queue delivered
    /// new audio since the prior read. The latter is diagnostic metadata only;
    /// it lets RF4.3 calibration distinguish a fresh capture callback from a
    /// frame that reuses the last block.
    pub fn latest_block(&mut self) -> (CapturedBlock, bool) {
        let mut received_new_block = false;
        while let Some(block) = self.consumer.try_pop() {
            // v1 is a mirror queue. Consumption is accounted only by
            // `try_next_hop`, otherwise an integration that temporarily reads
            // both routes would report every source frame twice.
            self.last = block;
            received_new_block = true;
        }
        if !received_new_block {
            self.telemetry.record_underflow();
        }
        (self.last.clone(), received_new_block)
    }

    /// ABI v2 scheduler entrypoint. It consumes exactly one ordered 512-frame
    /// multichannel hop, never drains the queue and never clones a buffer.
    #[allow(dead_code)] // public crate-local contract pending scheduler integration.
    pub fn try_next_hop(&mut self) -> Option<AudioHop> {
        match self.hop_consumer.try_pop() {
            Some(hop) => {
                self.telemetry.record_consume(HOP_FRAMES_PER_CHANNEL);
                Some(hop)
            }
            None => {
                self.telemetry.record_underflow();
                None
            }
        }
    }

    #[allow(dead_code)] // ABI v2 consumes this after the capture migration.
    pub fn telemetry(&self) -> CaptureTelemetrySnapshot {
        self.telemetry.snapshot()
    }
}

fn validate_capture_frame_size(frame_size: usize) -> Result<(), String> {
    if !(MIN_CAPTURE_FRAME_SIZE..=MAX_CAPTURE_FRAME_SIZE).contains(&frame_size)
        || !frame_size.is_power_of_two()
    {
        return Err("capture frame size must be a power of two within 512..=1024".to_owned());
    }
    Ok(())
}

/// RF6.2.2: Enumerates active render endpoints for loopback and active capture
/// endpoints for microphones, line-in and virtual inputs on an MTA worker.
pub fn enumerate_audio_devices() -> Result<Vec<AudioDevice>, String> {
    let (sender, receiver) = mpsc::sync_channel(1);
    thread::Builder::new()
        .name("echo-wasapi-device-enumeration".to_owned())
        .spawn(move || {
            let _ = sender.send(enumerate_audio_devices_mta());
        })
        .map_err(|error| format!("could not start WASAPI enumeration thread: {error}"))?;
    receiver
        .recv()
        .map_err(|error| format!("WASAPI enumeration thread ended unexpectedly: {error}"))?
}

fn capture_source_for_device_id(device_id: &str) -> Result<CaptureSource, String> {
    let devices = enumerate_audio_devices()?;
    source_from_devices(&devices, device_id)
}

fn source_from_devices(devices: &[AudioDevice], device_id: &str) -> Result<CaptureSource, String> {
    match devices.iter().find(|device| device.id == device_id) {
        Some(AudioDevice {
            kind: AudioDeviceKind::LoopbackRender,
            ..
        }) => Ok(CaptureSource::RenderLoopback(device_id.to_owned())),
        Some(AudioDevice {
            kind: AudioDeviceKind::DirectCapture,
            ..
        }) => Ok(CaptureSource::DirectInput(device_id.to_owned())),
        None => Err("selected audio device is unavailable".to_owned()),
    }
}

impl Drop for LoopbackCapture {
    fn drop(&mut self) {
        self.stop_requested.store(true, Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn capture_loop(
    mut producer: SpscProducer<CapturedBlock>,
    mut hop_producer: SpscProducer<AudioHop>,
    stop_requested: Arc<AtomicBool>,
    frame_size: usize,
    source: CaptureSource,
    telemetry: Arc<CaptureTelemetry>,
) {
    let result = capture_loop_inner(
        &mut producer,
        &mut hop_producer,
        &stop_requested,
        frame_size,
        &source,
        &telemetry,
    );
    if result.is_err() {
        publish_silence(&mut producer, frame_size, 0, &telemetry);
    }
}

fn capture_loop_inner(
    producer: &mut SpscProducer<CapturedBlock>,
    hop_producer: &mut SpscProducer<AudioHop>,
    stop_requested: &AtomicBool,
    frame_size: usize,
    source: &CaptureSource,
    telemetry: &CaptureTelemetry,
) -> Result<(), String> {
    initialize_mta()
        .ok()
        .map_err(|error| format!("WASAPI COM initialization failed: {error}"))?;
    let result = (|| {
        let enumerator = DeviceEnumerator::new().map_err(|error| error.to_string())?;
        let device = match source {
            CaptureSource::DefaultLoopback => enumerator
                .get_default_device(&Direction::Render)
                .map_err(|error| format!("default render device unavailable: {error}"))?,
            CaptureSource::RenderLoopback(id) | CaptureSource::DirectInput(id) => enumerator
                .get_device(id)
                .map_err(|error| format!("selected audio device is unavailable: {error}"))?,
        };
        // RF1.1: retain supported endpoint rates so the shared WASAPI stream
        // reaches rubato as 44.1/48/96 kHz float PCM. Unsupported device
        // formats are requested as the standard 48 kHz stereo fallback.
        let (input_sample_rate, input_channels) = capture_input_format(&device);
        let mut client = device
            .get_iaudioclient()
            .map_err(|error| error.to_string())?;
        let format = WaveFormat::new(
            32,
            32,
            &SampleType::Float,
            input_sample_rate,
            input_channels,
            None,
        );
        let (_, minimum_period) = client
            .get_device_period()
            .map_err(|error| error.to_string())?;
        let stream_mode = StreamMode::EventsShared {
            autoconvert: true,
            buffer_duration_hns: minimum_period,
        };
        // RF6.2: Render + Capture enables WASAPI loopback; Capture + Capture is
        // direct microphone/line-in acquisition. The wasapi crate applies the
        // loopback flag only for the former combination.
        client
            .initialize_client(&format, &Direction::Capture, &stream_mode)
            .map_err(|error| format!("could not initialize WASAPI loopback: {error}"))?;
        let event = client
            .set_get_eventhandle()
            .map_err(|error| error.to_string())?;
        let capture_client = client
            .get_audiocaptureclient()
            .map_err(|error| error.to_string())?;
        client.start_stream().map_err(|error| error.to_string())?;

        let started_at = Instant::now();
        let mut bytes = VecDeque::with_capacity(frame_size * input_channels * 8);
        let mut preprocessor = ChannelPreprocessor::new(input_sample_rate as u32, input_channels)
            .map_err(|error| error.to_string())?;
        let mut hop_assembler = HopAssembler::new(input_channels)?;
        let mut interleaved = Vec::with_capacity(frame_size * input_channels);
        let mut normalized = (0..input_channels)
            .map(|_| Vec::with_capacity(frame_size * 2))
            .collect::<Vec<_>>();
        let mut mono = Vec::with_capacity(frame_size);
        while !stop_requested.load(Ordering::Acquire) {
            if event.wait_for_event(25).is_err() {
                publish_silence(
                    producer,
                    frame_size,
                    started_at.elapsed().as_millis() as u64,
                    telemetry,
                );
                continue;
            }
            while capture_client
                .get_next_packet_size()
                .map_err(|error| error.to_string())?
                .unwrap_or(0)
                > 0
            {
                capture_client
                    .read_from_device_to_deque(&mut bytes)
                    .map_err(|error| error.to_string())?;
                drain_interleaved_multichannel(
                    &mut bytes,
                    &mut interleaved,
                    &mut normalized,
                    &mut mono,
                    &mut preprocessor,
                    &mut hop_assembler,
                    input_channels,
                    frame_size,
                    started_at.elapsed().as_millis() as u64,
                    |hop| publish_hop(hop_producer, hop, telemetry),
                    |block| {
                        publish_block(
                            producer,
                            block,
                            started_at.elapsed().as_millis() as u64,
                            telemetry,
                        )
                    },
                )
                .map_err(|error| error.to_string())?;
            }
        }
        let _ = client.stop_stream();
        Ok(())
    })();
    deinitialize();
    result
}

fn capture_input_format(device: &wasapi::Device) -> (usize, usize) {
    let fallback = (TARGET_SAMPLE_RATE, DEFAULT_CAPTURE_CHANNELS);
    let Ok(format) = device.get_device_format() else {
        return fallback;
    };
    let sample_rate = format.wave_fmt.Format.nSamplesPerSec as usize;
    let channels = format.wave_fmt.Format.nChannels as usize;
    if matches!(sample_rate, 44_100 | 48_000 | 96_000)
        && (1..=MAX_CAPTURE_CHANNELS).contains(&channels)
    {
        (sample_rate, channels)
    } else {
        fallback
    }
}

fn enumerate_audio_devices_mta() -> Result<Vec<AudioDevice>, String> {
    initialize_mta()
        .ok()
        .map_err(|error| format!("WASAPI COM initialization failed: {error}"))?;
    let result = (|| {
        let enumerator = DeviceEnumerator::new().map_err(|error| error.to_string())?;
        let default_render_id = default_device_id(&enumerator, Direction::Render);
        let default_capture_id = default_device_id(&enumerator, Direction::Capture);
        let mut devices = Vec::new();
        append_devices(
            &enumerator,
            Direction::Render,
            AudioDeviceKind::LoopbackRender,
            default_render_id.as_deref(),
            "Salida (loopback)",
            &mut devices,
        )?;
        append_devices(
            &enumerator,
            Direction::Capture,
            AudioDeviceKind::DirectCapture,
            default_capture_id.as_deref(),
            "Entrada directa",
            &mut devices,
        )?;
        Ok(devices)
    })();
    deinitialize();
    result
}

fn default_device_id(enumerator: &DeviceEnumerator, direction: Direction) -> Option<String> {
    enumerator
        .get_default_device(&direction)
        .ok()
        .and_then(|device| device.get_id().ok())
}

fn append_devices(
    enumerator: &DeviceEnumerator,
    direction: Direction,
    kind: AudioDeviceKind,
    default_id: Option<&str>,
    _label: &str,
    devices: &mut Vec<AudioDevice>,
) -> Result<(), String> {
    let collection = enumerator
        .get_device_collection(&direction)
        .map_err(|error| error.to_string())?;
    for device in &collection {
        let device = device.map_err(|error| error.to_string())?;
        let id = device.get_id().map_err(|error| error.to_string())?;
        let name = device
            .get_friendlyname()
            .map_err(|error| error.to_string())?;
        devices.push(AudioDevice {
            is_default: default_id == Some(id.as_str()),
            id,
            name,
            kind,
        });
    }
    Ok(())
}

/// Legacy mono shim used by the ABI v1 polling path.
#[allow(dead_code, clippy::too_many_arguments)] // retained exclusively for ABI v1 regression tests.
fn drain_interleaved_float_blocks(
    bytes: &mut VecDeque<u8>,
    interleaved: &mut Vec<f32>,
    normalized: &mut Vec<f32>,
    mono: &mut Vec<f32>,
    preprocessor: &mut AudioPreprocessor,
    channels: usize,
    frame_size: usize,
    mut publish: impl FnMut(&[f32]),
) -> Result<(), PreprocessError> {
    interleaved.clear();
    while bytes.len() >= channels * size_of::<f32>() {
        for _ in 0..channels {
            interleaved.push(pop_f32(bytes));
        }
    }
    if interleaved.is_empty() {
        return Ok(());
    }
    preprocessor.process_interleaved(interleaved, normalized)?;
    for sample in normalized.iter().copied() {
        mono.push(sample);
        if mono.len() == frame_size {
            publish(mono);
            mono.clear();
        }
    }
    Ok(())
}

/// RF1.1 callback path: resample every channel independently, publish exact
/// multichannel hops, then derive a separate legacy mono stream. This order is
/// intentional: `L=-R` is preserved in `AudioHop` and only cancels in the v1
/// compatibility projection.
#[allow(clippy::too_many_arguments)]
fn drain_interleaved_multichannel(
    bytes: &mut VecDeque<u8>,
    interleaved: &mut Vec<f32>,
    normalized: &mut [Vec<f32>],
    mono: &mut Vec<f32>,
    preprocessor: &mut ChannelPreprocessor,
    hop_assembler: &mut HopAssembler,
    channels: usize,
    frame_size: usize,
    timestamp_ms: u64,
    publish_hop: impl FnMut(AudioHop),
    mut publish_legacy: impl FnMut(&[f32]),
) -> Result<(), PreprocessError> {
    interleaved.clear();
    while bytes.len() >= channels * size_of::<f32>() {
        for _ in 0..channels {
            interleaved.push(pop_f32(bytes));
        }
    }
    if interleaved.is_empty() {
        return Ok(());
    }
    preprocessor.process_interleaved(interleaved, normalized)?;
    hop_assembler.push_lanes(normalized, timestamp_ms, publish_hop);
    let frames = normalized.first().map_or(0, Vec::len);
    for frame_index in 0..frames {
        let sample = normalized.iter().map(|lane| lane[frame_index]).sum::<f32>() / channels as f32;
        mono.push(sample);
        if mono.len() == frame_size {
            publish_legacy(mono);
            mono.clear();
        }
    }
    Ok(())
}

fn pop_f32(bytes: &mut VecDeque<u8>) -> f32 {
    let raw = std::array::from_fn(|_| bytes.pop_front().unwrap_or_default());
    f32::from_le_bytes(raw)
}

fn publish_block(
    producer: &mut SpscProducer<CapturedBlock>,
    samples: &[f32],
    timestamp_ms: u64,
    telemetry: &CaptureTelemetry,
) {
    // The legacy block ABI owns a Vec, but this producer never clones a
    // source slice (`to_vec`) or polls/discards data. ABI v2 replaces the
    // compatibility block with leased preallocated channel hops.
    let mut owned_samples = Vec::with_capacity(samples.len());
    owned_samples.extend_from_slice(samples);
    let block = CapturedBlock {
        samples: owned_samples,
        timestamp_ms,
    };
    if producer.try_push(block).is_err() {
        // The ABI v1 block shadows a hop already accounted as source audio.
        telemetry.record_overflow_drop();
    }
}

fn publish_hop(producer: &mut SpscProducer<AudioHop>, hop: AudioHop, telemetry: &CaptureTelemetry) {
    let timestamp_ms = hop.timestamp_ms;
    // Source accounting happens exactly once per normalized multichannel hop.
    // The legacy mono block published from the same callback is not another
    // source capture and therefore must not call `record_capture`.
    let overflowed = producer.try_push(hop).is_err();
    telemetry.record_capture(
        HOP_FRAMES_PER_CHANNEL,
        producer.occupied_len() * HOP_FRAMES_PER_CHANNEL,
        timestamp_ms,
    );
    if overflowed {
        telemetry.record_overflow_drop();
    }
}

fn publish_silence(
    producer: &mut SpscProducer<CapturedBlock>,
    frame_size: usize,
    timestamp_ms: u64,
    telemetry: &CaptureTelemetry,
) {
    let block = CapturedBlock {
        samples: vec![0.0; frame_size],
        timestamp_ms,
    };
    if producer.try_push(block).is_err() {
        telemetry.record_overflow_drop();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn downmixes_interleaved_stereo_blocks() {
        let mut bytes = VecDeque::new();
        for sample in [1.0_f32, -1.0, 0.5, 0.5] {
            bytes.extend(sample.to_le_bytes());
        }
        let mut interleaved = Vec::new();
        let mut normalized = Vec::new();
        let mut mono = Vec::new();
        let mut published = Vec::new();
        let mut preprocessor = AudioPreprocessor::new(TARGET_SAMPLE_RATE as u32, 2).unwrap();
        drain_interleaved_float_blocks(
            &mut bytes,
            &mut interleaved,
            &mut normalized,
            &mut mono,
            &mut preprocessor,
            2,
            2,
            |block| published.push(block.to_vec()),
        )
        .unwrap();
        assert_eq!(published, vec![vec![0.0, 0.5]]);
    }

    #[test]
    fn non_finite_capture_samples_are_sanitized() {
        let mut bytes = VecDeque::new();
        for sample in [f32::NAN, 1.0_f32] {
            bytes.extend(sample.to_le_bytes());
        }
        let mut interleaved = Vec::new();
        let mut normalized = Vec::new();
        let mut mono = Vec::new();
        let mut preprocessor = AudioPreprocessor::new(TARGET_SAMPLE_RATE as u32, 2).unwrap();
        drain_interleaved_float_blocks(
            &mut bytes,
            &mut interleaved,
            &mut normalized,
            &mut mono,
            &mut preprocessor,
            2,
            1,
            |_| {},
        )
        .unwrap();
        assert!(mono.is_empty());
    }

    #[test]
    fn rf6_2_selects_direct_capture_only_for_capture_endpoints() {
        let devices = [
            AudioDevice {
                id: "render-id".to_owned(),
                name: "Altavoces".to_owned(),
                is_default: true,
                kind: AudioDeviceKind::LoopbackRender,
            },
            AudioDevice {
                id: "capture-id".to_owned(),
                name: "Micrófono".to_owned(),
                is_default: true,
                kind: AudioDeviceKind::DirectCapture,
            },
        ];
        assert_eq!(
            source_from_devices(&devices, "render-id"),
            Ok(CaptureSource::RenderLoopback("render-id".to_owned()))
        );
        assert_eq!(
            source_from_devices(&devices, "capture-id"),
            Ok(CaptureSource::DirectInput("capture-id".to_owned()))
        );
        assert!(source_from_devices(&devices, "unavailable").is_err());
    }

    #[test]
    fn rf1_1_rejects_frame_sizes_outside_the_required_pcm_range() {
        for frame_size in [511, 1_025, 768] {
            assert!(validate_capture_frame_size(frame_size).is_err());
        }
        assert!(validate_capture_frame_size(512).is_ok());
        assert!(validate_capture_frame_size(1_024).is_ok());
    }

    #[test]
    fn multichannel_hops_are_exact_ordered_and_span_callback_boundaries() {
        let mut assembler = HopAssembler::new(2).unwrap();
        let mut output = Vec::new();
        for start in [0, 193, 386] {
            let count = if start == 386 { 638 } else { 193 };
            let lanes = vec![
                (start..start + count).map(|n| n as f32).collect::<Vec<_>>(),
                (start..start + count)
                    .map(|n| -(n as f32))
                    .collect::<Vec<_>>(),
            ];
            assembler.push_lanes(&lanes, 10, |hop| output.push(hop));
        }
        assert_eq!(output.len(), 2);
        for (hop_index, hop) in output.iter().enumerate() {
            assert_eq!(hop.channels, 2);
            for frame in 0..HOP_FRAMES_PER_CHANNEL {
                let expected = (hop_index * HOP_FRAMES_PER_CHANNEL + frame) as f32;
                assert_eq!(hop.samples[0][frame], expected);
                assert_eq!(hop.samples[1][frame], -expected);
            }
        }
    }

    #[test]
    fn multichannel_hop_sanitizes_non_finite_data_before_publication() {
        let mut processor = ChannelPreprocessor::new(TARGET_SAMPLE_RATE as u32, 2).unwrap();
        let mut lanes = vec![Vec::new(), Vec::new()];
        let input = std::iter::repeat_n([f32::NAN, f32::INFINITY], HOP_FRAMES_PER_CHANNEL)
            .flatten()
            .collect::<Vec<_>>();
        processor.process_interleaved(&input, &mut lanes).unwrap();
        let mut assembler = HopAssembler::new(2).unwrap();
        let mut hop = None;
        assembler.push_lanes(&lanes, 1, |value| hop = Some(value));
        assert!(hop
            .unwrap()
            .samples
            .iter()
            .flatten()
            .all(|sample| sample.is_finite()));
    }

    #[test]
    fn hop_queue_has_the_required_16384_frame_capacity_and_reports_overflow() {
        let (mut producer, mut consumer) = create_spsc_queue(HOP_QUEUE_CAPACITY);
        let telemetry = CaptureTelemetry::shared();
        for hop_number in 0..HOP_QUEUE_CAPACITY {
            let mut hop = AudioHop::empty(1, hop_number as u64);
            hop.samples[0][0] = hop_number as f32;
            publish_hop(&mut producer, hop, &telemetry);
        }
        publish_hop(&mut producer, AudioHop::empty(1, 99), &telemetry);
        let snapshot = telemetry.snapshot();
        // Source accounting includes the 33rd hop even though that hop was
        // dropped by the full SPSC queue.
        assert_eq!(snapshot.captured_frames, 16_896);
        assert_eq!(snapshot.high_water_frames, 16_384);
        assert_eq!(snapshot.overflows, 1);
        assert_eq!(snapshot.drops, 1);
        for expected in 0..HOP_QUEUE_CAPACITY {
            assert_eq!(consumer.try_pop().unwrap().samples[0][0], expected as f32);
        }
        assert!(consumer.try_pop().is_none());
    }

    #[test]
    fn legacy_shadow_publication_does_not_double_count_source_frames() {
        let (mut hop_producer, _) = create_spsc_queue(1);
        let (mut legacy_producer, _) = create_spsc_queue(1);
        let telemetry = CaptureTelemetry::shared();
        let hop = AudioHop::empty(2, 77);
        publish_hop(&mut hop_producer, hop, &telemetry);
        publish_block(
            &mut legacy_producer,
            &[0.25; HOP_FRAMES_PER_CHANNEL],
            77,
            &telemetry,
        );
        let snapshot = telemetry.snapshot();
        assert_eq!(snapshot.captured_frames, HOP_FRAMES_PER_CHANNEL as u64);
        assert_eq!(snapshot.overflows, 0);
        assert_eq!(snapshot.drops, 0);
    }
}
