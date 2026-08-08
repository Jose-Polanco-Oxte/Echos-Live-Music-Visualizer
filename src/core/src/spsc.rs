//! Lock-free single-producer/single-consumer transport for audio frames.
//!
//! RF1.1/RNF-REL.2: the audio callback must be able to account for congestion
//! without waiting on the DSP worker or acquiring a mutex.
use ringbuf::{traits::Split, HeapCons, HeapProd, HeapRb};
use std::sync::{
    atomic::{AtomicU64, Ordering},
    Arc,
};

pub type SpscProducer<T> = HeapProd<T>;
pub type SpscConsumer<T> = HeapCons<T>;

pub fn create_spsc_queue<T>(capacity: usize) -> (SpscProducer<T>, SpscConsumer<T>) {
    assert!(
        capacity > 0,
        "SPSC queue capacity must be greater than zero"
    );
    HeapRb::<T>::new(capacity).split()
}

#[allow(dead_code)] // exported to capture; ABI v2 exposes it in the next block.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct CaptureTelemetrySnapshot {
    pub captured_frames: u64,
    pub consumed_frames: u64,
    pub underflows: u64,
    pub overflows: u64,
    pub drops: u64,
    pub high_water_frames: u64,
    pub timestamp_ms: u64,
}

/// Atomic-only telemetry shared by the SPSC producer and consumer. Values are
/// advisory diagnostics: no code may spin, wait or retry in order to update
/// them on the WASAPI callback path.
#[derive(Default)]
pub struct CaptureTelemetry {
    captured_frames: AtomicU64,
    consumed_frames: AtomicU64,
    underflows: AtomicU64,
    overflows: AtomicU64,
    drops: AtomicU64,
    high_water_frames: AtomicU64,
    timestamp_ms: AtomicU64,
}

impl CaptureTelemetry {
    pub fn shared() -> Arc<Self> {
        Arc::new(Self::default())
    }
    pub fn record_capture(&self, frames: usize, queued_frames: usize, timestamp_ms: u64) {
        self.captured_frames
            .fetch_add(frames as u64, Ordering::Relaxed);
        self.timestamp_ms.store(timestamp_ms, Ordering::Release);
        let queued = queued_frames as u64;
        let mut previous = self.high_water_frames.load(Ordering::Relaxed);
        while queued > previous {
            match self.high_water_frames.compare_exchange_weak(
                previous,
                queued,
                Ordering::Relaxed,
                Ordering::Relaxed,
            ) {
                Ok(_) => break,
                Err(actual) => previous = actual,
            }
        }
    }
    pub fn record_consume(&self, frames: usize) {
        self.consumed_frames
            .fetch_add(frames as u64, Ordering::Relaxed);
    }
    pub fn record_underflow(&self) {
        self.underflows.fetch_add(1, Ordering::Relaxed);
    }
    pub fn record_overflow_drop(&self) {
        self.overflows.fetch_add(1, Ordering::Relaxed);
        self.drops.fetch_add(1, Ordering::Relaxed);
    }
    #[allow(dead_code)] // read by the upcoming worker/FFI telemetry endpoint.
    pub fn snapshot(&self) -> CaptureTelemetrySnapshot {
        CaptureTelemetrySnapshot {
            captured_frames: self.captured_frames.load(Ordering::Acquire),
            consumed_frames: self.consumed_frames.load(Ordering::Acquire),
            underflows: self.underflows.load(Ordering::Acquire),
            overflows: self.overflows.load(Ordering::Acquire),
            drops: self.drops.load(Ordering::Acquire),
            high_water_frames: self.high_water_frames.load(Ordering::Acquire),
            timestamp_ms: self.timestamp_ms.load(Ordering::Acquire),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use ringbuf::traits::{Consumer, Producer};
    use std::thread;
    #[test]
    fn spsc_queue_preserves_order_and_reports_full_without_waiting() {
        let (mut producer, mut consumer) = create_spsc_queue(2);
        assert_eq!(producer.try_push(10), Ok(()));
        assert_eq!(producer.try_push(20), Ok(()));
        assert_eq!(producer.try_push(30), Err(30));
        assert_eq!(consumer.try_pop(), Some(10));
        assert_eq!(consumer.try_pop(), Some(20));
        assert_eq!(consumer.try_pop(), None);
    }
    #[test]
    fn spsc_queue_transfers_frames_between_capture_and_render_threads() {
        let (mut producer, mut consumer) = create_spsc_queue(64);
        let producer_thread = thread::spawn(move || {
            for frame in 0_u32..10_000 {
                loop {
                    if producer.try_push(frame).is_ok() {
                        break;
                    }
                    thread::yield_now();
                }
            }
        });
        let mut received = Vec::with_capacity(10_000);
        while received.len() < 10_000 {
            if let Some(frame) = consumer.try_pop() {
                received.push(frame);
            } else {
                thread::yield_now();
            }
        }
        producer_thread.join().unwrap();
        assert_eq!(received, (0_u32..10_000).collect::<Vec<_>>());
    }

    #[test]
    fn telemetry_is_lock_free_and_preserves_capture_accounting() {
        let telemetry = CaptureTelemetry::shared();
        telemetry.record_capture(512, 512, 20);
        telemetry.record_capture(512, 1024, 31);
        telemetry.record_consume(512);
        telemetry.record_underflow();
        telemetry.record_overflow_drop();
        assert_eq!(
            telemetry.snapshot(),
            CaptureTelemetrySnapshot {
                captured_frames: 1024,
                consumed_frames: 512,
                underflows: 1,
                overflows: 1,
                drops: 1,
                high_water_frames: 1024,
                timestamp_ms: 31,
            }
        );
    }
}
