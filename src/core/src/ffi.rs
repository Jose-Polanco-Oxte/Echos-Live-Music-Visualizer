use std::{
    ffi::{c_char, c_void, CString},
    panic::{catch_unwind, AssertUnwindSafe},
    ptr,
    sync::{
        atomic::{AtomicBool, AtomicU32, AtomicU8, Ordering},
        Arc,
    },
    thread::{self, JoinHandle},
    time::Duration,
    time::Instant,
};

use crate::{
    capture::{enumerate_audio_devices, AudioDeviceKind, LoopbackCapture, MAX_CAPTURE_CHANNELS},
    BandProfile, BandScale, DspProcessor, DspScheduler, DspSettings, FrameMetadata, FrameStore,
    LoudnessProcessor, LufsMode, MasterPeakScaler, ProcessedFrame, SpectralScalingMode,
    SAMPLE_RATE_HZ,
};

const ERROR_BUFFER_EMPTY: u32 = 0;
const ERROR_BUFFER_TOO_SMALL: u32 = 1;
const ERROR_BUFFER_WRITTEN: u32 = 2;

/// Stable ABI snapshot consumed by .NET. `band_energies` is owned by the
/// engine and remains valid until the next call that reconfigures or destroys
/// that engine.
#[repr(C)]
pub struct AudioFrameData {
    pub rms: f32,
    pub spectral_centroid_hz: f32,
    pub onset_detected: u8,
    pub band_count: u32,
    pub band_energies: *const f32,
    pub timestamp_ms: u64,
}

/// ABI v2 leased view. Every pointer remains valid only until its matching
/// `release_analysis_frame_v2` call. `lease_id` is opaque to clients.
#[repr(C)]
pub struct AnalysisFrameDataV2 {
    pub abi_version: u32,
    pub flags: u32,
    pub rms: f32,
    pub rms_dbfs: f32,
    pub spectral_centroid_hz: f32,
    pub onset_detected: u8,
    pub _reserved: [u8; 3],
    pub onset_score: f32,
    pub band_count: u32,
    pub raw_band_energies: *const f32,
    pub conditioned_band_energies: *const f32,
    pub band_peak_energies: *const f32,
    pub band_centers_hz: *const f32,
    pub sequence: u64,
    pub capture_timestamp_us: u64,
    pub analysis_sample_rate_hz: u32,
    pub hop_frames: u32,
    pub compute_latency_us: u64,
    pub profile_generation: u64,
    pub lease_id: u64,
}

const ANALYSIS_ABI_VERSION: u32 = 2;

struct DspWorker {
    stop_requested: Arc<AtomicBool>,
    thread: Option<JoinHandle<()>>,
}

struct WorkerConfig {
    conditioning_mode: AtomicU8,
    lufs_mode: AtomicU8,
    manual_gain: AtomicU32,
    manual_gamma: AtomicU32,
}

impl WorkerConfig {
    fn new() -> Self {
        Self {
            // Production always uses the approved hybrid path. Other enum
            // values remain ABI-compatible for older callers, but are not
            // exposed by the application UI.
            conditioning_mode: AtomicU8::new(3),
            lufs_mode: AtomicU8::new(0),
            manual_gain: AtomicU32::new(1.0_f32.to_bits()),
            manual_gamma: AtomicU32::new(1.0_f32.to_bits()),
        }
    }

    fn snapshot(&self) -> (ConditioningMode, LufsMode) {
        let conditioning = match self.conditioning_mode.load(Ordering::Acquire) {
            1 => ConditioningMode::StabilizedPivot,
            2 => ConditioningMode::MasterPeak,
            3 => ConditioningMode::HybridMacroMaster,
            _ => ConditioningMode::HybridMacroMaster,
        };
        let lufs = if self.lufs_mode.load(Ordering::Acquire) == 1 {
            LufsMode::Manual {
                gain: f32::from_bits(self.manual_gain.load(Ordering::Acquire)),
                gamma: f32::from_bits(self.manual_gamma.load(Ordering::Acquire)),
            }
        } else {
            LufsMode::default()
        };
        (conditioning, lufs)
    }
}

impl DspWorker {
    fn start(
        capture: LoopbackCapture,
        store: Arc<FrameStore>,
        band_count: usize,
        config: Arc<WorkerConfig>,
    ) -> Result<Self, String> {
        let stop_requested = Arc::new(AtomicBool::new(false));
        let worker_stop = Arc::clone(&stop_requested);
        let thread = thread::Builder::new()
            .name("echo-dsp-worker".to_owned())
            .spawn(move || dsp_worker_loop(capture, store, band_count, config, worker_stop))
            .map_err(|error| format!("could not start DSP worker: {error}"))?;
        Ok(Self {
            stop_requested,
            thread: Some(thread),
        })
    }
}

impl Drop for DspWorker {
    fn drop(&mut self) {
        self.stop_requested.store(true, Ordering::Release);
        if let Some(thread) = self.thread.take() {
            let _ = thread.join();
        }
    }
}

fn dsp_worker_loop(
    mut capture: LoopbackCapture,
    store: Arc<FrameStore>,
    band_count: usize,
    config: Arc<WorkerConfig>,
    stop_requested: Arc<AtomicBool>,
) {
    let Ok(mut scheduler) = DspScheduler::new(BandProfile::Erb, band_count) else {
        return;
    };
    let centers = scheduler.band_centers_hz();
    let ranges = scheduler.band_ranges_hz();
    let mut loudness: [LoudnessProcessor; MAX_CAPTURE_CHANNELS] =
        std::array::from_fn(|_| LoudnessProcessor::new(SAMPLE_RATE_HZ));
    let mut master_peak = MasterPeakScaler::default();
    let mut conditioned = vec![0.0_f32; crate::frame_store::MAX_BAND_COUNT];
    let mut peaks = vec![0.0_f32; crate::frame_store::MAX_BAND_COUNT];
    let mut active_channels = 0_u8;
    while !stop_requested.load(Ordering::Acquire) {
        match scheduler.process_next_hop(&mut capture) {
            Ok(true) => {
                let Some(frame) = scheduler.latest() else {
                    continue;
                };
                let features = frame.analysis.features;
                let rms_dbfs = if features.rms > 0.0 {
                    20.0 * features.rms.log10()
                } else {
                    -120.0
                };
                let bands = &frame.analysis.band_energies;
                let Some(hop) = scheduler.latest_hop() else {
                    continue;
                };
                let (conditioning_mode, lufs_mode) = config.snapshot();
                if hop.channels != active_channels {
                    for processor in &mut loudness {
                        *processor = LoudnessProcessor::new(SAMPLE_RATE_HZ);
                    }
                    master_peak.reset();
                    active_channels = hop.channels;
                }
                let adjustment = process_loudness_hop(
                    &mut loudness[..hop.channels as usize],
                    hop,
                    lufs_mode,
                    conditioning_mode,
                );
                conditioned[..bands.len()].copy_from_slice(bands);
                peaks[..bands.len()].copy_from_slice(bands);
                let master = match conditioning_mode {
                    ConditioningMode::NormativeLufs => {
                        LoudnessProcessor::condition_band_energies(
                            &mut conditioned[..bands.len()],
                            adjustment,
                        );
                        0.0
                    }
                    ConditioningMode::StabilizedPivot => {
                        LoudnessProcessor::condition_band_energies_with_pivot(
                            &mut conditioned[..bands.len()],
                            adjustment,
                        );
                        0.0
                    }
                    ConditioningMode::MasterPeak => master_peak.condition_band_energies(
                        &mut peaks[..bands.len()],
                        &ranges,
                        features.rms,
                    ),
                    ConditioningMode::HybridMacroMaster => master_peak
                        .condition_hybrid_band_energies(
                            &mut conditioned[..bands.len()],
                            &ranges,
                            adjustment.gain,
                            adjustment.short_term_lufs < -50.0,
                        ),
                };
                if matches!(conditioning_mode, ConditioningMode::MasterPeak) {
                    conditioned[..bands.len()].copy_from_slice(&peaks[..bands.len()]);
                }
                let metadata = FrameMetadata {
                    short_term_lufs: adjustment.short_term_lufs,
                    gain: adjustment.gain,
                    gamma: adjustment.gamma,
                    master_peak: master,
                    rms: features.rms,
                    rms_dbfs,
                    spectral_centroid_hz: features.spectral_centroid_hz,
                    onset_detected: features.onset_detected,
                    onset_score: features.onset_score,
                    sequence: frame.sequence,
                    capture_timestamp_us: frame.timestamp_ms.saturating_mul(1_000),
                    analysis_sample_rate_hz: SAMPLE_RATE_HZ,
                    hop_frames: crate::HOP_FRAMES as u32,
                    compute_latency_us: frame.compute_latency_us,
                    profile_generation: frame.generation,
                    flags: 0,
                    band_count: bands.len() as u32,
                };
                let _ = store.publish(
                    metadata,
                    bands,
                    &conditioned[..bands.len()],
                    &peaks[..bands.len()],
                    &centers,
                );
            }
            Ok(false) => thread::sleep(Duration::from_millis(1)),
            Err(_) => thread::sleep(Duration::from_millis(1)),
        }
    }
}

fn process_loudness_hop(
    processors: &mut [LoudnessProcessor],
    hop: &crate::capture::AudioHop,
    mode: LufsMode,
    conditioning: ConditioningMode,
) -> crate::LoudnessAdjustment {
    let mut lufs_power = 0.0_f32;
    let mut gain = 0.0_f32;
    let mut gamma = 0.0_f32;
    for (processor, lane) in processors.iter_mut().zip(&hop.samples) {
        let adjustment = match conditioning {
            ConditioningMode::StabilizedPivot => processor
                .process_stabilized_samples(&lane[..crate::capture::HOP_FRAMES_PER_CHANNEL], mode),
            ConditioningMode::HybridMacroMaster => processor
                .process_hybrid_samples(&lane[..crate::capture::HOP_FRAMES_PER_CHANNEL], mode),
            _ => processor.process_samples(&lane[..crate::capture::HOP_FRAMES_PER_CHANNEL], mode),
        };
        lufs_power += 10.0_f32.powf(adjustment.short_term_lufs / 10.0);
        gain += adjustment.gain;
        gamma += adjustment.gamma;
    }
    let count = processors.len().max(1) as f32;
    crate::LoudnessAdjustment {
        short_term_lufs: if lufs_power > 0.0 {
            (10.0 * (lufs_power / count).log10()).max(-70.0)
        } else {
            -70.0
        },
        gain: gain / count,
        gamma: gamma / count,
    }
}

/// RF4.3.1 diagnostic snapshot. This is intentionally separate from the
/// real-time frame ABI so normal rendering remains allocation-free and does
/// not pay for calibration telemetry unless the UI explicitly requests it.
#[repr(C)]
pub struct LoudnessDiagnosticsData {
    pub short_term_lufs: f32,
    pub gain: f32,
    pub gamma: f32,
    pub pre_energy_mean: f32,
    pub pre_energy_max: f32,
    pub post_energy_mean: f32,
    pub post_energy_max: f32,
    pub master_peak: f32,
    pub capture_block_is_new: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum ConditioningMode {
    NormativeLufs = 0,
    StabilizedPivot = 1,
    MasterPeak = 2,
    HybridMacroMaster = 3,
}

#[repr(C)]
pub struct AudioDeviceProperties {
    pub device_id: *const c_char,
    pub name: *const c_char,
    pub is_default: u8,
}

const AUDIO_DEVICE_ABI_VERSION: u32 = 2;

/// RF6.2.2 versioned device descriptor. The v1 layout and exports remain
/// unchanged; new clients use `struct_size` and `abi_version` before reading
/// the explicit render-loopback/direct-capture kind.
#[repr(C)]
pub struct AudioDevicePropertiesV2 {
    pub struct_size: u32,
    pub abi_version: u32,
    pub device_id: *const c_char,
    pub name: *const c_char,
    pub is_default: u8,
    pub kind: u8,
    pub _reserved: [u8; 2],
}

struct AudioEngine {
    settings: DspSettings,
    processor: DspProcessor,
    loudness: LoudnessProcessor,
    lufs_mode: LufsMode,
    conditioning_mode: ConditioningMode,
    master_peak: MasterPeakScaler,
    frame_store: Arc<FrameStore>,
    dsp_worker: Option<DspWorker>,
    v1_sequence: u64,
    audio_device_id: Option<String>,
    worker_config: Arc<WorkerConfig>,
    silence: Vec<f32>,
    frame: ProcessedFrame,
    last_adjustment: crate::LoudnessAdjustment,
    pre_energy_mean: f32,
    pre_energy_max: f32,
    post_energy_mean: f32,
    post_energy_max: f32,
    last_master_peak: f32,
    capture_block_is_new: bool,
    started_at: Instant,
    capture_timestamp_ms: u64,
    last_error: CString,
}

impl AudioEngine {
    fn new(sample_rate: u32, frame_size: u32) -> Result<Self, String> {
        let settings = DspSettings {
            sample_rate,
            frame_size: frame_size as usize,
            ..DspSettings::default()
        };
        let processor = DspProcessor::new(settings.clone()).map_err(|error| error.to_string())?;
        let loudness = LoudnessProcessor::new(settings.sample_rate);
        let silence = vec![0.0; settings.frame_size];
        let frame = ProcessedFrame::with_band_count(settings.band_count);
        let capture = LoopbackCapture::start(settings.frame_size, None).ok();
        let frame_store = Arc::new(FrameStore::new(settings.band_count));
        let worker_config = Arc::new(WorkerConfig::new());
        let mut engine = Self {
            settings,
            processor,
            loudness,
            lufs_mode: LufsMode::default(),
            conditioning_mode: ConditioningMode::HybridMacroMaster,
            master_peak: MasterPeakScaler::default(),
            frame_store: Arc::clone(&frame_store),
            dsp_worker: None,
            v1_sequence: 0,
            audio_device_id: None,
            worker_config: Arc::clone(&worker_config),
            silence,
            frame,
            last_adjustment: crate::LoudnessAdjustment {
                short_term_lufs: -70.0,
                gain: 1.0,
                gamma: 1.0,
            },
            pre_energy_mean: 0.0,
            pre_energy_max: 0.0,
            post_energy_mean: 0.0,
            post_energy_max: 0.0,
            last_master_peak: 0.0,
            capture_block_is_new: false,
            started_at: Instant::now(),
            capture_timestamp_ms: 0,
            last_error: CString::default(),
        };
        engine.process_silence();
        if let Some(capture) = capture {
            match DspWorker::start(
                capture,
                frame_store,
                engine.settings.band_count,
                worker_config,
            ) {
                Ok(worker) => engine.dsp_worker = Some(worker),
                Err(error) => engine.set_error(error),
            }
        }
        Ok(engine)
    }

    fn process_silence(&mut self) {
        if let Err(error) = self.processor.process_into(&self.silence, &mut self.frame) {
            self.set_error(error.to_string());
            return;
        }
        let adjustment = match self.conditioning_mode {
            ConditioningMode::StabilizedPivot | ConditioningMode::MasterPeak => self
                .loudness
                .process_stabilized_samples(&self.silence, self.lufs_mode),
            ConditioningMode::HybridMacroMaster => self
                .loudness
                .process_hybrid_samples(&self.silence, self.lufs_mode),
            ConditioningMode::NormativeLufs => {
                self.loudness.process_samples(&self.silence, self.lufs_mode)
            }
        };
        self.condition_frame_energies(adjustment);
        let metadata = FrameMetadata {
            short_term_lufs: adjustment.short_term_lufs,
            gain: adjustment.gain,
            gamma: adjustment.gamma,
            master_peak: self.last_master_peak,
            rms: self.frame.rms,
            rms_dbfs: -120.0,
            spectral_centroid_hz: self.frame.spectral_centroid_hz,
            onset_detected: self.frame.onset_detected,
            onset_score: 0.0,
            sequence: 1,
            capture_timestamp_us: 0,
            analysis_sample_rate_hz: self.settings.sample_rate,
            hop_frames: crate::HOP_FRAMES as u32,
            compute_latency_us: 0,
            profile_generation: 1,
            flags: 0,
            band_count: self.settings.band_count as u32,
        };
        let centers: Vec<f32> = self
            .processor
            .band_ranges()
            .iter()
            .map(|range| range.center_hz())
            .collect();
        let _ = self.frame_store.publish(
            metadata,
            &self.frame.band_energies,
            &self.frame.band_energies,
            &self.frame.band_energies,
            &centers,
        );
    }

    /// ABI v1 cache update. It never drains capture, executes FFT, or clones
    /// PCM; it only copies the already published spectral scalar/vector when a
    /// newer v2 sequence exists.
    fn refresh_v1_cache(&mut self) {
        let Some(lease) = self.frame_store.acquire() else {
            return;
        };
        if lease.metadata.sequence != 0 && lease.metadata.sequence != self.v1_sequence {
            self.frame.rms = lease.metadata.rms;
            self.frame.spectral_centroid_hz = lease.metadata.spectral_centroid_hz;
            self.frame.onset_detected = lease.metadata.onset_detected;
            // SAFETY: this lease owns `conditioned` until release and the v1
            // vector has the same fixed capacity as the store.
            unsafe {
                let source =
                    std::slice::from_raw_parts(lease.conditioned, lease.band_count as usize);
                for (destination, value) in self.frame.band_energies.iter_mut().zip(source) {
                    *destination = *value;
                }
                for destination in self.frame.band_energies.iter_mut().skip(source.len()) {
                    *destination = 0.0;
                }
            }
            self.capture_timestamp_ms = lease.metadata.capture_timestamp_us / 1_000;
            self.capture_block_is_new = true;
            self.v1_sequence = lease.metadata.sequence;
        } else {
            self.capture_block_is_new = false;
        }
        lease.release();
    }

    /// RF4.1/RF4.3: every frame uses K-weighted short-term LUFS before its
    /// band vector is published to C#. The vector is owned and reused by the DSP.
    #[allow(dead_code)]
    fn process_samples(&mut self, samples: &[f32]) {
        if let Err(error) = self.processor.process_into(samples, &mut self.frame) {
            self.set_error(error.to_string());
            return;
        }
        let adjustment = self.adjustment_for_samples(samples);
        self.condition_frame_energies(adjustment);
    }

    #[allow(dead_code)]
    fn adjustment_for_samples(&mut self, samples: &[f32]) -> crate::LoudnessAdjustment {
        match self.conditioning_mode {
            ConditioningMode::StabilizedPivot | ConditioningMode::MasterPeak => self
                .loudness
                .process_stabilized_samples(samples, self.lufs_mode),
            ConditioningMode::HybridMacroMaster => self
                .loudness
                .process_hybrid_samples(samples, self.lufs_mode),
            ConditioningMode::NormativeLufs => {
                self.loudness.process_samples(samples, self.lufs_mode)
            }
        }
    }

    /// RF4.3 / RF4.3.1: retain scalar energy statistics around the normative
    /// condition equation without copying the preallocated band vector.
    fn condition_frame_energies(&mut self, adjustment: crate::LoudnessAdjustment) {
        (self.pre_energy_mean, self.pre_energy_max) = energy_statistics(&self.frame.band_energies);
        self.last_master_peak = match self.conditioning_mode {
            ConditioningMode::NormativeLufs => {
                LoudnessProcessor::condition_band_energies(
                    &mut self.frame.band_energies,
                    adjustment,
                );
                0.0
            }
            ConditioningMode::StabilizedPivot => {
                LoudnessProcessor::condition_band_energies_with_pivot(
                    &mut self.frame.band_energies,
                    adjustment,
                );
                0.0
            }
            ConditioningMode::MasterPeak => self.master_peak.condition_band_energies(
                &mut self.frame.band_energies,
                self.processor.band_ranges(),
                self.frame.rms,
            ),
            ConditioningMode::HybridMacroMaster => self.master_peak.condition_hybrid_band_energies(
                &mut self.frame.band_energies,
                self.processor.band_ranges(),
                adjustment.gain,
                adjustment.short_term_lufs < -50.0,
            ),
        };
        (self.post_energy_mean, self.post_energy_max) =
            energy_statistics(&self.frame.band_energies);
        self.last_adjustment = adjustment;
    }

    fn reconfigure(&mut self, settings: DspSettings) -> Result<(), String> {
        let processor = DspProcessor::new(settings.clone()).map_err(|error| error.to_string())?;

        // If an active dsp_worker is present, try to restart/reconfigure it first
        // so that capture failure doesn't leave the DSP state half-updated or fail
        // configuration validation tests when hardware capture is unavailable.
        if self.dsp_worker.is_some() {
            let capture = LoopbackCapture::start(settings.frame_size, self.audio_device_id.clone())?;
            let replacement = DspWorker::start(
                capture,
                Arc::clone(&self.frame_store),
                settings.band_count,
                Arc::clone(&self.worker_config),
            );
            let new_worker = replacement?;
            let _ = self.dsp_worker.replace(new_worker);
        }

        self.silence.resize(settings.frame_size, 0.0);
        self.frame = ProcessedFrame::with_band_count(settings.band_count);
        self.settings = settings;
        self.processor = processor;
        self.loudness = LoudnessProcessor::new(self.settings.sample_rate);
        self.master_peak.reset();
        self.frame_store.set_band_count(self.settings.band_count);
        self.process_silence();
        Ok(())
    }

    #[allow(dead_code)]
    fn restart_worker(&mut self) -> Result<(), String> {
        let capture =
            LoopbackCapture::start(self.settings.frame_size, self.audio_device_id.clone())?;
        let replacement = DspWorker::start(
            capture,
            Arc::clone(&self.frame_store),
            self.settings.band_count,
            Arc::clone(&self.worker_config),
        );
        replace_worker_transactionally(&mut self.dsp_worker, replacement)
    }

    fn set_audio_device(&mut self, device_id: Option<String>) -> Result<(), String> {
        let capture = LoopbackCapture::start(self.settings.frame_size, device_id.clone())?;
        let replacement = DspWorker::start(
            capture,
            Arc::clone(&self.frame_store),
            self.settings.band_count,
            Arc::clone(&self.worker_config),
        );
        replace_worker_transactionally(&mut self.dsp_worker, replacement)?;
        self.audio_device_id = device_id;
        self.last_error = CString::default();
        Ok(())
    }

    fn set_error(&mut self, error: String) {
        self.last_error = CString::new(error).unwrap_or_default();
    }

    fn timestamp_ms(&self) -> u64 {
        self.capture_timestamp_ms
            .max(self.started_at.elapsed().as_millis() as u64)
    }
}

fn replace_worker_transactionally<T, E>(
    active: &mut Option<T>,
    replacement: Result<T, E>,
) -> Result<(), E> {
    let replacement = replacement?;
    let _previous = active.replace(replacement);
    Ok(())
}

fn audio_device_kind_abi(kind: AudioDeviceKind) -> u8 {
    match kind {
        AudioDeviceKind::RenderLoopback => 1,
        AudioDeviceKind::DirectCapture => 2,
    }
}

fn energy_statistics(energies: &[f32]) -> (f32, f32) {
    if energies.is_empty() {
        return (0.0, 0.0);
    }
    let mut sum = 0.0_f32;
    let mut maximum = 0.0_f32;
    for energy in energies {
        let energy = if energy.is_finite() {
            energy.max(0.0)
        } else {
            0.0
        };
        sum += energy;
        maximum = maximum.max(energy);
    }
    (sum / energies.len() as f32, maximum)
}

fn with_engine_mut<T>(
    handle: *mut c_void,
    fallback: T,
    action: impl FnOnce(&mut AudioEngine) -> T,
) -> T {
    if handle.is_null() {
        return fallback;
    }
    // The handle is produced only by `init_audio_engine`; all other callers
    // receive an error value rather than dereferencing a null pointer.
    unsafe { action(&mut *(handle as *mut AudioEngine)) }
}

fn band_scale(scale_type: u8) -> Option<BandScale> {
    match scale_type {
        0 => Some(BandScale::Linear),
        1 => Some(BandScale::Logarithmic),
        2 => Some(BandScale::Mel),
        _ => None,
    }
}

/// ABI version 1: `AudioFrameData` uses an explicit one-byte onset flag.
#[no_mangle]
pub extern "C" fn echo_core_version() -> u32 {
    1
}

#[no_mangle]
pub extern "C" fn init_audio_engine(sample_rate: u32, frame_size: u32) -> *mut c_void {
    catch_unwind(AssertUnwindSafe(|| {
        AudioEngine::new(sample_rate, frame_size)
            .map(|engine| Box::into_raw(Box::new(engine)) as *mut c_void)
            .unwrap_or(ptr::null_mut())
    }))
    .unwrap_or(ptr::null_mut())
}

#[no_mangle]
pub unsafe extern "C" fn get_latest_frame(
    handle: *mut c_void,
    out_frame: *mut AudioFrameData,
) -> u8 {
    if out_frame.is_null() {
        return 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            engine.refresh_v1_cache();
            unsafe {
                out_frame.write(AudioFrameData {
                    rms: engine.frame.rms,
                    spectral_centroid_hz: engine.frame.spectral_centroid_hz,
                    onset_detected: u8::from(engine.frame.onset_detected),
                    band_count: engine.frame.band_energies.len() as u32,
                    band_energies: engine.frame.band_energies.as_ptr(),
                    timestamp_ms: engine.timestamp_ms(),
                });
            }
            1
        })
    }))
    .unwrap_or(0)
}

/// Acquires the latest ABI v2 analysis frame.  The caller must release the
/// exact `lease_id` supplied in `out_frame` before another render tick.
#[no_mangle]
pub unsafe extern "C" fn acquire_latest_analysis_frame_v2(
    handle: *mut c_void,
    out_frame: *mut AnalysisFrameDataV2,
) -> u8 {
    if out_frame.is_null() {
        return 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            let Some(lease) = engine.frame_store.acquire() else {
                return 0;
            };
            let metadata = lease.metadata;
            unsafe {
                out_frame.write(AnalysisFrameDataV2 {
                    abi_version: ANALYSIS_ABI_VERSION,
                    flags: metadata.flags,
                    rms: metadata.rms,
                    rms_dbfs: metadata.rms_dbfs,
                    spectral_centroid_hz: metadata.spectral_centroid_hz,
                    onset_detected: u8::from(metadata.onset_detected),
                    _reserved: [0; 3],
                    onset_score: metadata.onset_score,
                    band_count: lease.band_count,
                    raw_band_energies: lease.raw,
                    conditioned_band_energies: lease.conditioned,
                    band_peak_energies: lease.peaks,
                    band_centers_hz: lease.centers,
                    sequence: metadata.sequence,
                    capture_timestamp_us: metadata.capture_timestamp_us,
                    analysis_sample_rate_hz: metadata.analysis_sample_rate_hz,
                    hop_frames: metadata.hop_frames,
                    compute_latency_us: metadata.compute_latency_us,
                    profile_generation: metadata.profile_generation,
                    lease_id: lease.lease_id,
                });
            }
            // AcquiredFrame has no Drop implementation: its reader count is
            // intentionally transferred to the ABI caller.
            1
        })
    }))
    .unwrap_or(0)
}

/// Releases an ABI v2 lease.  It does not touch capture or schedule DSP.
#[no_mangle]
pub extern "C" fn release_analysis_frame_v2(handle: *mut c_void, lease_id: u64) -> u8 {
    if lease_id == 0 {
        return 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            engine.frame_store.release_lease(lease_id);
            1
        })
    }))
    .unwrap_or(0)
}

/// RF4.3.1: reads the last DSP adjustment and scalar band statistics without
/// processing another block. Calibration UI polls this at a low cadence.
#[no_mangle]
pub unsafe extern "C" fn get_loudness_diagnostics(
    handle: *mut c_void,
    out_diagnostics: *mut LoudnessDiagnosticsData,
) -> u8 {
    if out_diagnostics.is_null() {
        return 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            if let Some(lease) = engine
                .frame_store
                .acquire()
                .filter(|lease| lease.metadata.sequence != 0)
            {
                let metadata = lease.metadata;
                let (pre_mean, pre_max) = unsafe {
                    energy_statistics(std::slice::from_raw_parts(
                        lease.raw,
                        lease.band_count as usize,
                    ))
                };
                let (post_mean, post_max) = unsafe {
                    energy_statistics(std::slice::from_raw_parts(
                        lease.conditioned,
                        lease.band_count as usize,
                    ))
                };
                unsafe {
                    out_diagnostics.write(LoudnessDiagnosticsData {
                        short_term_lufs: metadata.short_term_lufs,
                        gain: metadata.gain,
                        gamma: metadata.gamma,
                        pre_energy_mean: pre_mean,
                        pre_energy_max: pre_max,
                        post_energy_mean: post_mean,
                        post_energy_max: post_max,
                        master_peak: metadata.master_peak,
                        capture_block_is_new: u8::from(metadata.sequence != 0),
                    });
                }
                lease.release();
                return 1;
            }
            unsafe {
                out_diagnostics.write(LoudnessDiagnosticsData {
                    short_term_lufs: engine.last_adjustment.short_term_lufs,
                    gain: engine.last_adjustment.gain,
                    gamma: engine.last_adjustment.gamma,
                    pre_energy_mean: engine.pre_energy_mean,
                    pre_energy_max: engine.pre_energy_max,
                    post_energy_mean: engine.post_energy_mean,
                    post_energy_max: engine.post_energy_max,
                    master_peak: engine.last_master_peak,
                    capture_block_is_new: u8::from(engine.capture_block_is_new),
                });
            }
            1
        })
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn set_band_configuration(
    handle: *mut c_void,
    band_count: u32,
    scale_type: u8,
) -> u8 {
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            let Some(band_scale) = band_scale(scale_type) else {
                engine.set_error(format!("unsupported band scale type {scale_type}"));
                return 0;
            };
            let settings = DspSettings {
                band_count: band_count as usize,
                band_scale,
                ..engine.settings.clone()
            };
            match engine.reconfigure(settings) {
                Ok(()) => 1,
                Err(error) => {
                    engine.set_error(error);
                    0
                }
            }
        })
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub extern "C" fn set_smoothing_parameters(handle: *mut c_void, attack: f32, decay: f32) -> u8 {
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            let settings = DspSettings {
                attack,
                decay,
                ..engine.settings.clone()
            };
            match engine.reconfigure(settings) {
                Ok(()) => 1,
                Err(error) => {
                    engine.set_error(error);
                    0
                }
            }
        })
    }))
    .unwrap_or(0)
}

/// RF4.3: selects the loudness conditioning strategy without reallocating the
/// published band vector. `mode=0` restores normative automatic defaults;
/// `mode=1` uses client-provided manual gain and gamma.
#[no_mangle]
pub extern "C" fn set_lufs_mode(handle: *mut c_void, mode: u8, gain: f32, gamma: f32) -> u8 {
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            engine.lufs_mode = match mode {
                0 => LufsMode::default(),
                1 if gain.is_finite() && gamma.is_finite() && gain >= 0.0 && gamma > 0.0 => {
                    LufsMode::Manual { gain, gamma }
                }
                1 => {
                    engine.set_error(
                        "manual LUFS gain must be >= 0 and gamma must be > 0".to_owned(),
                    );
                    return 0;
                }
                _ => {
                    engine.set_error(format!("unsupported LUFS mode {mode}"));
                    return 0;
                }
            };
            engine
                .worker_config
                .lufs_mode
                .store(u8::from(mode == 1), Ordering::Release);
            if mode == 1 {
                engine
                    .worker_config
                    .manual_gain
                    .store(gain.to_bits(), Ordering::Release);
                engine
                    .worker_config
                    .manual_gamma
                    .store(gamma.to_bits(), Ordering::Release);
            }
            1
        })
    }))
    .unwrap_or(0)
}

/// RF4.3.2/RF4.3.3: selects an experimental route without allocating or
/// changing `AudioFrameData`: 0 normative, 1 pivoted LUFS, 2 Pico Maestro,
/// 3 hybrid LUFS macro + Pico Maestro micro.
#[no_mangle]
pub extern "C" fn set_conditioning_mode(handle: *mut c_void, mode: u8) -> u8 {
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            engine.conditioning_mode = match mode {
                0 => ConditioningMode::NormativeLufs,
                1 => ConditioningMode::StabilizedPivot,
                2 => ConditioningMode::MasterPeak,
                3 => ConditioningMode::HybridMacroMaster,
                _ => {
                    engine.set_error(format!("unsupported conditioning mode {mode}"));
                    return 0;
                }
            };
            engine
                .worker_config
                .conditioning_mode
                .store(mode, Ordering::Release);
            engine.loudness.reset_stabilized_state();
            engine.master_peak.reset();
            engine.last_master_peak = 0.0;
            1
        })
    }))
    .unwrap_or(0)
}

/// Configures the visual spectral scaling mode: 0 Linear, 1 Decibels (-50 dB to 0 dB), 2 Perceptual Pink Noise (+3 dB/octave tilt).
#[no_mangle]
pub extern "C" fn echo_core_set_spectral_scaling_mode(handle: *mut c_void, mode: u32) -> u8 {
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            let scaling_mode = match mode {
                0 => SpectralScalingMode::Linear,
                1 => SpectralScalingMode::Decibels,
                2 => SpectralScalingMode::PerceptualPinkNoise,
                _ => {
                    engine.set_error(format!("unsupported spectral scaling mode {mode}"));
                    return 0;
                }
            };
            engine.master_peak.set_scaling_mode(scaling_mode);
            1
        })
    }))
    .unwrap_or(0)
}

/// RF6.2.3: changes only the MTA capture worker; the DSP engine and UI polling
/// contract remain alive. `device_id` must be a NUL-terminated UTF-8 WASAPI ID.
#[no_mangle]
pub unsafe extern "C" fn set_audio_device(handle: *mut c_void, device_id: *const c_char) -> u8 {
    if device_id.is_null() {
        return 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        with_engine_mut(handle, 0, |engine| {
            let device_id = unsafe { std::ffi::CStr::from_ptr(device_id) }
                .to_str()
                .map(str::to_owned)
                .map_err(|error| error.to_string());
            match device_id.and_then(|id| {
                let selected = if id == "default" { None } else { Some(id) };
                engine.set_audio_device(selected)
            }) {
                Ok(()) => 1,
                Err(error) => {
                    engine.set_error(error.to_string());
                    0
                }
            }
        })
    }))
    .unwrap_or(0)
}

/// Returns heap-owned device properties. The caller must invoke
/// `free_device_list` exactly once for a successful result.
#[no_mangle]
pub unsafe extern "C" fn get_audio_devices(
    handle: *mut c_void,
    out_devices: *mut *mut AudioDeviceProperties,
    out_count: *mut u32,
) -> u8 {
    if out_devices.is_null() || out_count.is_null() {
        return 0;
    }
    unsafe {
        *out_devices = ptr::null_mut();
        *out_count = 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let devices = match enumerate_audio_devices() {
            Ok(devices) => devices,
            Err(error) => {
                with_engine_mut(handle, (), |engine| engine.set_error(error));
                return 0;
            }
        };
        let mut properties = Vec::with_capacity(devices.len());
        for device in devices {
            let Ok(id) = CString::new(device.id) else {
                continue;
            };
            let Ok(name) = CString::new(device.name) else {
                continue;
            };
            properties.push(AudioDeviceProperties {
                device_id: id.into_raw(),
                name: name.into_raw(),
                is_default: u8::from(device.is_default),
            });
        }
        let count = properties.len() as u32;
        let properties = properties.into_boxed_slice();
        unsafe {
            *out_devices = Box::into_raw(properties) as *mut AudioDeviceProperties;
            *out_count = count;
        }
        1
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn free_device_list(devices: *mut AudioDeviceProperties, count: u32) {
    if devices.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let properties = Vec::from_raw_parts(devices, count as usize, count as usize);
        for property in properties {
            if !property.device_id.is_null() {
                drop(CString::from_raw(property.device_id.cast_mut()));
            }
            if !property.name.is_null() {
                drop(CString::from_raw(property.name.cast_mut()));
            }
        }
    }));
}

/// RF6.2.2: v2 device enumeration preserves v1 while adding a self-describing
/// layout and the endpoint capture kind. The caller owns the returned list and
/// must release it with `free_device_list_v2` exactly once.
#[no_mangle]
pub unsafe extern "C" fn get_audio_devices_v2(
    handle: *mut c_void,
    out_devices: *mut *mut AudioDevicePropertiesV2,
    out_count: *mut u32,
) -> u8 {
    if out_devices.is_null() || out_count.is_null() {
        return 0;
    }
    unsafe {
        *out_devices = ptr::null_mut();
        *out_count = 0;
    }
    catch_unwind(AssertUnwindSafe(|| {
        let devices = match enumerate_audio_devices() {
            Ok(devices) => devices,
            Err(error) => {
                with_engine_mut(handle, (), |engine| engine.set_error(error));
                return 0;
            }
        };
        let mut properties = Vec::with_capacity(devices.len());
        for device in devices {
            let Ok(id) = CString::new(device.id) else {
                continue;
            };
            let Ok(name) = CString::new(device.name) else {
                continue;
            };
            properties.push(AudioDevicePropertiesV2 {
                struct_size: std::mem::size_of::<AudioDevicePropertiesV2>() as u32,
                abi_version: AUDIO_DEVICE_ABI_VERSION,
                device_id: id.into_raw(),
                name: name.into_raw(),
                is_default: u8::from(device.is_default),
                kind: audio_device_kind_abi(device.kind),
                _reserved: [0; 2],
            });
        }
        let count = properties.len() as u32;
        let properties = properties.into_boxed_slice();
        unsafe {
            *out_devices = Box::into_raw(properties) as *mut AudioDevicePropertiesV2;
            *out_count = count;
        }
        1
    }))
    .unwrap_or(0)
}

#[no_mangle]
pub unsafe extern "C" fn free_device_list_v2(devices: *mut AudioDevicePropertiesV2, count: u32) {
    if devices.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        let properties = Vec::from_raw_parts(devices, count as usize, count as usize);
        for property in properties {
            if !property.device_id.is_null() {
                drop(CString::from_raw(property.device_id.cast_mut()));
            }
            if !property.name.is_null() {
                drop(CString::from_raw(property.name.cast_mut()));
            }
        }
    }));
}

/// Copies a UTF-8 error message without allocating. Returns 2 when a complete
/// NUL-terminated message was written, 1 when the buffer is too small and 0
/// when no error is available.
#[no_mangle]
pub unsafe extern "C" fn get_last_error(
    handle: *mut c_void,
    out_buffer: *mut c_char,
    buffer_len: u32,
) -> u32 {
    if out_buffer.is_null() || buffer_len == 0 {
        return ERROR_BUFFER_TOO_SMALL;
    }
    with_engine_mut(handle, ERROR_BUFFER_EMPTY, |engine| {
        let bytes = engine.last_error.as_bytes_with_nul();
        if bytes.len() == 1 {
            return ERROR_BUFFER_EMPTY;
        }
        if bytes.len() > buffer_len as usize {
            return ERROR_BUFFER_TOO_SMALL;
        }
        unsafe {
            ptr::copy_nonoverlapping(bytes.as_ptr().cast::<c_char>(), out_buffer, bytes.len());
        }
        ERROR_BUFFER_WRITTEN
    })
}

#[no_mangle]
pub unsafe extern "C" fn destroy_audio_engine(handle: *mut c_void) {
    if handle.is_null() {
        return;
    }
    let _ = catch_unwind(AssertUnwindSafe(|| unsafe {
        drop(Box::from_raw(handle as *mut AudioEngine));
    }));
}

#[cfg(test)]
mod tests {
    use super::*;

    fn offline_engine() -> AudioEngine {
        let settings = DspSettings::default();
        AudioEngine {
            processor: DspProcessor::new(settings.clone()).unwrap(),
            loudness: LoudnessProcessor::new(settings.sample_rate),
            lufs_mode: LufsMode::default(),
            conditioning_mode: ConditioningMode::HybridMacroMaster,
            master_peak: MasterPeakScaler::default(),
            silence: vec![0.0; settings.frame_size],
            frame: ProcessedFrame::with_band_count(settings.band_count),
            last_adjustment: crate::LoudnessAdjustment {
                short_term_lufs: -70.0,
                gain: 1.0,
                gamma: 1.0,
            },
            pre_energy_mean: 0.0,
            pre_energy_max: 0.0,
            post_energy_mean: 0.0,
            post_energy_max: 0.0,
            last_master_peak: 0.0,
            capture_block_is_new: false,
            settings,
            frame_store: Arc::new(FrameStore::new(3)),
            dsp_worker: None,
            v1_sequence: 0,
            audio_device_id: None,
            worker_config: Arc::new(WorkerConfig::new()),
            started_at: Instant::now(),
            capture_timestamp_ms: 0,
            last_error: CString::default(),
        }
    }

    #[test]
    fn lifecycle_returns_a_valid_silent_frame() {
        let handle = init_audio_engine(48_000, 1_024);
        assert!(!handle.is_null());
        let mut frame = AudioFrameData {
            rms: -1.0,
            spectral_centroid_hz: -1.0,
            onset_detected: 9,
            band_count: 0,
            band_energies: ptr::null(),
            timestamp_ms: 0,
        };
        assert_eq!(unsafe { get_latest_frame(handle, &mut frame) }, 1);
        assert_eq!(frame.band_count, 3);
        assert!(!frame.band_energies.is_null());
        assert_eq!(frame.rms, 0.0);
        unsafe { destroy_audio_engine(handle) };
    }

    #[test]
    fn reconfiguration_validates_values_and_exposes_error() {
        let handle = init_audio_engine(48_000, 1_024);
        assert_eq!(set_band_configuration(handle, 12, 2), 1);
        assert_eq!(set_band_configuration(handle, 2, 2), 0);
        let mut buffer = [0_i8; 256];
        assert_eq!(
            unsafe { get_last_error(handle, buffer.as_mut_ptr(), buffer.len() as u32) },
            ERROR_BUFFER_WRITTEN
        );
        unsafe { destroy_audio_engine(handle) };
    }

    #[test]
    fn rf4_3_conditions_the_same_band_vector_that_ffi_publishes() {
        let mut engine = offline_engine();
        // Manual G=0 is an unambiguous oracle for Efinal=clamp((E*G)^gamma).
        engine.conditioning_mode = ConditioningMode::NormativeLufs;
        engine.lufs_mode = LufsMode::Manual {
            gain: 0.0,
            gamma: 1.0,
        };
        let samples: Vec<f32> = (0..engine.settings.frame_size)
            .map(|index| (index as f32 * 0.05).sin())
            .collect();
        engine.process_samples(&samples);
        assert!(engine
            .frame
            .band_energies
            .iter()
            .all(|energy| *energy == 0.0));
    }

    #[test]
    fn rf4_3_exposes_manual_and_automatic_lufs_modes_through_the_abi() {
        let mut engine = Box::new(offline_engine());
        let handle = (&mut *engine as *mut AudioEngine).cast::<c_void>();
        assert_eq!(set_lufs_mode(handle, 1, 2.0, 1.5), 1);
        assert_eq!(
            engine.lufs_mode,
            LufsMode::Manual {
                gain: 2.0,
                gamma: 1.5
            }
        );
        assert_eq!(set_lufs_mode(handle, 0, 0.0, 0.0), 1);
        assert_eq!(engine.lufs_mode, LufsMode::default());
        assert_eq!(set_lufs_mode(handle, 1, -1.0, 1.0), 0);
    }

    #[test]
    fn rf4_3_2_and_rf4_3_3_expose_comparison_modes_through_the_abi() {
        let mut engine = Box::new(offline_engine());
        let handle = (&mut *engine as *mut AudioEngine).cast::<c_void>();
        assert_eq!(set_conditioning_mode(handle, 1), 1);
        assert_eq!(engine.conditioning_mode, ConditioningMode::StabilizedPivot);
        assert_eq!(set_conditioning_mode(handle, 2), 1);
        assert_eq!(engine.conditioning_mode, ConditioningMode::MasterPeak);
        assert_eq!(set_conditioning_mode(handle, 3), 1);
        assert_eq!(
            engine.conditioning_mode,
            ConditioningMode::HybridMacroMaster
        );
        assert_eq!(set_conditioning_mode(handle, 9), 0);
    }

    #[test]
    fn rf4_3_1_diagnostics_expose_pre_and_post_conditioning_statistics() {
        let mut engine = Box::new(offline_engine());
        engine.lufs_mode = LufsMode::Manual {
            gain: 0.5,
            gamma: 1.0,
        };
        engine.process_samples(&vec![0.8; engine.settings.frame_size]);
        let handle = (&mut *engine as *mut AudioEngine).cast::<c_void>();
        let mut diagnostics = LoudnessDiagnosticsData {
            short_term_lufs: 0.0,
            gain: 0.0,
            gamma: 0.0,
            pre_energy_mean: 0.0,
            pre_energy_max: 0.0,
            post_energy_mean: 0.0,
            post_energy_max: 0.0,
            master_peak: 0.0,
            capture_block_is_new: 1,
        };
        assert_eq!(
            unsafe { get_loudness_diagnostics(handle, &mut diagnostics) },
            1
        );
        assert_eq!(diagnostics.gain, 0.5);
        assert_eq!(diagnostics.gamma, 1.0);
        assert!(diagnostics.pre_energy_mean.is_finite());
        assert!(diagnostics.post_energy_mean.is_finite());
        assert!(diagnostics.pre_energy_max.is_finite());
        assert!(diagnostics.post_energy_max.is_finite());
        assert!((0.0..=1.0).contains(&diagnostics.post_energy_max));
    }

    #[test]
    fn worker_lufs_handles_antiphase_channels_without_cancellation() {
        let mut processors: [LoudnessProcessor; 2] =
            std::array::from_fn(|_| LoudnessProcessor::new(SAMPLE_RATE_HZ));
        let mut hop = crate::capture::AudioHop {
            samples: [[0.0; crate::capture::HOP_FRAMES_PER_CHANNEL];
                crate::capture::MAX_CAPTURE_CHANNELS],
            channels: 2,
            timestamp_ms: 0,
        };
        for index in 0..crate::capture::HOP_FRAMES_PER_CHANNEL {
            hop.samples[0][index] = 0.5;
            hop.samples[1][index] = -0.5;
        }
        let adjustment = process_loudness_hop(
            &mut processors,
            &hop,
            LufsMode::default(),
            ConditioningMode::HybridMacroMaster,
        );
        assert!(adjustment.short_term_lufs.is_finite());
        assert!(adjustment.short_term_lufs > -70.0);
    }

    #[test]
    fn worker_hybrid_conditioning_preserves_neutral_band_relationships() {
        let mut scaler = MasterPeakScaler::default();
        scaler.set_scaling_mode(SpectralScalingMode::Linear);
        let ranges = vec![
            crate::BandRange {
                start_hz: 100.0,
                end_hz: 200.0,
            },
            crate::BandRange {
                start_hz: 1_000.0,
                end_hz: 2_000.0,
            },
        ];
        let mut bands = [0.16_f32, 0.04];
        scaler.condition_hybrid_band_energies(&mut bands, &ranges, 1.0, false);
        assert!((bands[0].atanh() / bands[1].atanh() - 2.0).abs() < 0.000_1);
    }

    #[test]
    fn rf6_2_device_v2_layout_and_kind_mapping_are_stable() {
        assert_eq!(AUDIO_DEVICE_ABI_VERSION, 2);
        assert_eq!(audio_device_kind_abi(AudioDeviceKind::RenderLoopback), 1);
        assert_eq!(audio_device_kind_abi(AudioDeviceKind::DirectCapture), 2);
        if cfg!(target_pointer_width = "64") {
            assert_eq!(std::mem::size_of::<AudioDeviceProperties>(), 24);
            assert_eq!(std::mem::size_of::<AudioDevicePropertiesV2>(), 32);
        }
    }

    #[test]
    fn rf6_2_failed_worker_replacement_preserves_the_active_worker() {
        let mut active = Some("working");
        let result = replace_worker_transactionally(&mut active, Err::<&str, _>("failed"));
        assert_eq!(result, Err("failed"));
        assert_eq!(active, Some("working"));

        assert_eq!(
            replace_worker_transactionally(&mut active, Ok::<_, &str>("replacement")),
            Ok(())
        );
        assert_eq!(active, Some("replacement"));
    }

    #[test]
    fn rf6_2_device_v2_allocation_uses_matching_free_export() {
        let properties = vec![AudioDevicePropertiesV2 {
            struct_size: std::mem::size_of::<AudioDevicePropertiesV2>() as u32,
            abi_version: AUDIO_DEVICE_ABI_VERSION,
            device_id: CString::new("device").unwrap().into_raw(),
            name: CString::new("Microphone").unwrap().into_raw(),
            is_default: 1,
            kind: audio_device_kind_abi(AudioDeviceKind::DirectCapture),
            _reserved: [0; 2],
        }]
        .into_boxed_slice();
        let pointer = Box::into_raw(properties) as *mut AudioDevicePropertiesV2;
        unsafe { free_device_list_v2(pointer, 1) };
    }
}
