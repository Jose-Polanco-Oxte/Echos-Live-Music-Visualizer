#![allow(linker_messages)]

//! Echo DSP core.
//!
//! The public FFI boundary is deliberately small: the UI consumes immutable
//! `AudioFrameData` snapshots while capture and DSP remain on the Rust side.

mod analysis;
mod bands;
mod capture;
mod features;
mod ffi;
mod frame_store;
mod loudness;
mod master_peak;
mod multiresolution;
mod preprocess;
mod scheduler;
mod spsc;
mod stft;

pub use analysis::{
    BandRange, BandScale, DspProcessor, DspSettings, DspSettingsError, ProcessError, ProcessedFrame,
};
pub use bands::{
    generate_band_ranges, generate_fractional_octave_ranges, integrate_bands_continuous,
    BandProfile, BandRange as PerceptualBandRange,
};
pub use features::{FastFeatures, FeatureExtractor};
pub use ffi::AudioFrameData;
pub use frame_store::{FrameMetadata, FrameStore};
pub use loudness::{LoudnessAdjustment, LoudnessProcessor, LufsMode};
pub use master_peak::{MasterPeakScaler, SpectralScalingMode};
pub use multiresolution::{
    MultiResolutionAnalyzer, MultiResolutionError, MultiResolutionFrame, HIGH_FFT_SIZE, HOP_FRAMES,
    LOW_FFT_SIZE, MID_FFT_SIZE, SAMPLE_RATE_HZ,
};
pub use preprocess::{AudioPreprocessor, PreprocessError, TARGET_SAMPLE_RATE_HZ};
pub use scheduler::{DspScheduler, ScheduledFrame, SchedulerError};
pub use spsc::{create_spsc_queue, SpscConsumer, SpscProducer};
pub use stft::{blackman_harris_4, StftAnalyzer, StftError};
