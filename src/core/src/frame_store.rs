//! Lock-free triple-buffer publication for ABI v2 analysis frames.
//!
//! A slot state is either a positive reader count or [`WRITING`].  The writer
//! first claims an idle slot with CAS; readers similarly increment only an
//! idle slot.  This prevents the classic "reader increments after writer saw
//! zero" race without placing a mutex on the real-time path.

use std::{
    cell::UnsafeCell,
    sync::atomic::{AtomicU64, AtomicUsize, Ordering},
};

pub const SLOT_COUNT: usize = 3;
pub const MAX_BAND_COUNT: usize = 128;
const WRITING: usize = usize::MAX;

#[derive(Debug, Clone, Copy, Default)]
pub struct FrameMetadata {
    pub short_term_lufs: f32,
    pub gain: f32,
    pub gamma: f32,
    pub master_peak: f32,
    pub rms: f32,
    pub rms_dbfs: f32,
    pub spectral_centroid_hz: f32,
    pub onset_detected: bool,
    pub onset_score: f32,
    pub sequence: u64,
    pub capture_timestamp_us: u64,
    pub analysis_sample_rate_hz: u32,
    pub hop_frames: u32,
    pub compute_latency_us: u64,
    pub profile_generation: u64,
    pub flags: u32,
    pub band_count: u32,
}

pub struct FrameSlot {
    state: AtomicUsize,
    raw: UnsafeCell<Vec<f32>>,
    conditioned: UnsafeCell<Vec<f32>>,
    peaks: UnsafeCell<Vec<f32>>,
    centers: UnsafeCell<Vec<f32>>,
    metadata: UnsafeCell<FrameMetadata>,
}

// Mutation is guarded by `state == WRITING`; readers hold an incremented
// state for the whole pointer lifetime.
unsafe impl Sync for FrameSlot {}

impl FrameSlot {
    fn new(band_count: usize) -> Self {
        Self {
            state: AtomicUsize::new(0),
            raw: UnsafeCell::new(vec![0.0; band_count]),
            conditioned: UnsafeCell::new(vec![0.0; band_count]),
            peaks: UnsafeCell::new(vec![0.0; band_count]),
            centers: UnsafeCell::new(vec![0.0; band_count]),
            metadata: UnsafeCell::new(FrameMetadata::default()),
        }
    }
}

pub struct AcquiredFrame<'a> {
    store: &'a FrameStore,
    slot: usize,
    pub metadata: FrameMetadata,
    pub raw: *const f32,
    pub conditioned: *const f32,
    pub peaks: *const f32,
    pub centers: *const f32,
    pub band_count: u32,
    pub lease_id: u64,
}

impl AcquiredFrame<'_> {
    pub fn release(self) {
        self.store.release(self.slot, self.lease_id);
    }
}

/// Fixed-capacity analysis publication store.  Changing an analysis profile
/// creates a new generation in metadata, never reallocates or invalidates a
/// previously leased slot.
pub struct FrameStore {
    slots: [FrameSlot; SLOT_COUNT],
    active_band_count: AtomicUsize,
    latest: AtomicUsize,
    published: AtomicU64,
    next_lease: AtomicU64,
    dropped_publications: AtomicU64,
}

impl FrameStore {
    pub fn new(band_count: usize) -> Self {
        assert!((1..=MAX_BAND_COUNT).contains(&band_count));
        Self {
            slots: std::array::from_fn(|_| FrameSlot::new(MAX_BAND_COUNT)),
            active_band_count: AtomicUsize::new(band_count),
            latest: AtomicUsize::new(0),
            published: AtomicU64::new(0),
            next_lease: AtomicU64::new(1),
            dropped_publications: AtomicU64::new(0),
        }
    }

    pub fn band_capacity(&self) -> usize {
        // All slots have equal preallocated capacity.
        MAX_BAND_COUNT
    }

    pub fn active_band_count(&self) -> usize {
        self.active_band_count.load(Ordering::Acquire)
    }

    pub fn set_band_count(&self, band_count: usize) -> bool {
        if !(1..=MAX_BAND_COUNT).contains(&band_count) {
            return false;
        }
        self.active_band_count.store(band_count, Ordering::Release);
        true
    }

    pub fn publish(
        &self,
        metadata: FrameMetadata,
        raw: &[f32],
        conditioned: &[f32],
        peaks: &[f32],
        centers: &[f32],
    ) -> bool {
        // RF5.1/RNF-PERF.3: publication is worker-owned and never performs
        // analysis; readers consume only an already complete frame.
        let active_band_count = self.active_band_count();
        if raw.len() != active_band_count
            || conditioned.len() != raw.len()
            || peaks.len() != raw.len()
            || centers.len() != raw.len()
        {
            self.dropped_publications.fetch_add(1, Ordering::Relaxed);
            return false;
        }
        let Some(index) = self.claim_writer() else {
            self.dropped_publications.fetch_add(1, Ordering::Relaxed);
            return false;
        };
        let slot = &self.slots[index];
        // SAFETY: `claim_writer` changed state from 0 to WRITING. Readers can
        // only acquire slots whose state is not WRITING, so these vectors are
        // exclusively writable until the Release publication below.
        unsafe {
            (&mut *slot.raw.get())[..active_band_count].copy_from_slice(raw);
            (&mut *slot.conditioned.get())[..active_band_count].copy_from_slice(conditioned);
            (&mut *slot.peaks.get())[..active_band_count].copy_from_slice(peaks);
            (&mut *slot.centers.get())[..active_band_count].copy_from_slice(centers);
            *slot.metadata.get() = FrameMetadata {
                band_count: active_band_count as u32,
                ..metadata
            };
        }
        slot.state.store(0, Ordering::Release);
        self.latest.store(index, Ordering::Release);
        self.published.fetch_add(1, Ordering::Relaxed);
        true
    }

    pub fn acquire(&self) -> Option<AcquiredFrame<'_>> {
        // RF5.2/RNF-REL.2: Acquire pairs with the writer's Release and never
        // waits on a lock or invokes the DSP scheduler.
        for _ in 0..SLOT_COUNT * 2 {
            let index = self.latest.load(Ordering::Acquire);
            let slot = &self.slots[index];
            if !Self::claim_reader(slot) {
                continue;
            }
            // A publication after `latest` was read is fine: this lease owns
            // the older coherent slot.  A writer cannot alter it now.
            let metadata = unsafe { *slot.metadata.get() };
            let lease_id = (self.next_lease.fetch_add(1, Ordering::Relaxed) << 2) | index as u64;
            return Some(AcquiredFrame {
                store: self,
                slot: index,
                metadata,
                raw: unsafe { (&*slot.raw.get()).as_ptr() },
                conditioned: unsafe { (&*slot.conditioned.get()).as_ptr() },
                peaks: unsafe { (&*slot.peaks.get()).as_ptr() },
                centers: unsafe { (&*slot.centers.get()).as_ptr() },
                band_count: metadata.band_count,
                lease_id,
            });
        }
        None
    }

    pub fn release(&self, slot: usize, _lease_id: u64) {
        if slot >= SLOT_COUNT {
            return;
        }
        let state = &self.slots[slot].state;
        let prior = state.fetch_sub(1, Ordering::Release);
        debug_assert!(prior > 0 && prior != WRITING, "invalid frame lease release");
    }

    pub fn release_lease(&self, lease_id: u64) {
        self.release((lease_id & 0b11) as usize, lease_id);
    }

    pub fn published_count(&self) -> u64 {
        self.published.load(Ordering::Relaxed)
    }
    pub fn dropped_publications(&self) -> u64 {
        self.dropped_publications.load(Ordering::Relaxed)
    }

    fn claim_writer(&self) -> Option<usize> {
        (0..SLOT_COUNT).find(|&index| {
            self.slots[index]
                .state
                .compare_exchange(0, WRITING, Ordering::Acquire, Ordering::Relaxed)
                .is_ok()
        })
    }

    fn claim_reader(slot: &FrameSlot) -> bool {
        let mut current = slot.state.load(Ordering::Acquire);
        loop {
            if current == WRITING || current == WRITING - 1 {
                return false;
            }
            match slot.state.compare_exchange_weak(
                current,
                current + 1,
                Ordering::Acquire,
                Ordering::Relaxed,
            ) {
                Ok(_) => return true,
                Err(next) => current = next,
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn metadata(sequence: u64) -> FrameMetadata {
        FrameMetadata {
            sequence,
            band_count: 2,
            ..FrameMetadata::default()
        }
    }
    fn publish(store: &FrameStore, sequence: u64) -> bool {
        let data = [sequence as f32, 2.0];
        store.publish(metadata(sequence), &data, &data, &data, &[20.0, 40.0])
    }

    #[test]
    fn lease_prevents_writer_from_overwriting_slot() {
        let store = FrameStore::new(2);
        assert!(publish(&store, 1));
        let lease = store.acquire().unwrap();
        assert_eq!(lease.metadata.sequence, 1);
        assert!(publish(&store, 2));
        assert!(publish(&store, 3));
        // The two non-leased slots may rotate while this reader holds the
        // first one; publication must remain non-blocking.
        assert!(publish(&store, 4));
        assert_eq!(unsafe { *lease.raw }, 1.0);
        lease.release();
        assert!(publish(&store, 5));
    }

    #[test]
    fn frames_are_coherent_and_release_allows_reuse() {
        let store = FrameStore::new(2);
        assert!(publish(&store, 9));
        let lease = store.acquire().unwrap();
        assert_eq!(unsafe { *lease.conditioned.add(1) }, 2.0);
        assert_eq!(lease.metadata.sequence, 9);
        lease.release();
        assert_eq!(store.dropped_publications(), 0);
    }

    #[test]
    fn million_acquires_are_cached_and_do_not_publish_or_allocate() {
        let store = FrameStore::new(2);
        assert!(publish(&store, 11));
        let published = store.published_count();
        for _ in 0..1_000_000 {
            let lease = store
                .acquire()
                .expect("published frame must remain readable");
            assert_eq!(lease.metadata.sequence, 11);
            lease.release();
        }
        assert_eq!(store.published_count(), published);
        assert_eq!(store.dropped_publications(), 0);
    }

    #[test]
    fn active_band_resize_keeps_old_lease_coherent() {
        let store = FrameStore::new(3);
        let old = [1.0_f32, 2.0, 3.0];
        assert!(store.publish(
            FrameMetadata {
                sequence: 1,
                band_count: 3,
                ..FrameMetadata::default()
            },
            &old,
            &old,
            &old,
            &[20.0, 30.0, 40.0],
        ));
        let lease = store.acquire().unwrap();
        assert_eq!(lease.band_count, 3);
        assert_eq!(unsafe { *lease.raw.add(2) }, 3.0);
        assert!(store.set_band_count(48));
        let values = vec![7.0_f32; 48];
        assert!(store.publish(
            FrameMetadata {
                sequence: 2,
                band_count: 48,
                ..FrameMetadata::default()
            },
            &values,
            &values,
            &values,
            &values,
        ));
        let current = store.acquire().unwrap();
        assert_eq!(current.band_count, 48);
        assert_eq!(unsafe { *current.raw }, 7.0);
        current.release();
        assert_eq!(unsafe { *lease.raw.add(2) }, 3.0);
        lease.release();
    }
}
