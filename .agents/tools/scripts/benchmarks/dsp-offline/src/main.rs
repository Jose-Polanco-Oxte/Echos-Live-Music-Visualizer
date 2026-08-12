//! Deterministic offline benchmark for the public Echo DSP API.
//!
//! This intentionally lives outside `src/core`: it is a measurement harness,
//! not product code.  Input generation happens before the timed region so
//! `L_c` represents `DspProcessor::process_into` only.

use echo_core::{BandScale, DspProcessor, DspSettings, ProcessedFrame};
use std::env;
use std::time::Instant;

const SAMPLE_RATE: f32 = 48_000.0;
const FRAME_SIZE: usize = 1_024;
const DEFAULT_ITERATIONS: usize = 2_000;

#[derive(Clone, Copy)]
enum Fixture {
    Tone,
    Sweep,
    PinkNoise,
    Subgrave,
    Rock,
    Electronic,
    Percussion,
    Antiphase,
}

impl Fixture {
    fn name(self) -> &'static str {
        match self {
            Self::Tone => "tone_1khz",
            Self::Sweep => "sweep_20_500hz",
            Self::PinkNoise => "pink_noise",
            Self::Subgrave => "subgrave_32hz",
            Self::Rock => "rock_synthetic",
            Self::Electronic => "electronic_synthetic",
            Self::Percussion => "percussion_synthetic",
            Self::Antiphase => "antiphase_mono_surrogate",
        }
    }
}

fn fixtures() -> [Fixture; 8] {
    [
        Fixture::Tone,
        Fixture::Sweep,
        Fixture::PinkNoise,
        Fixture::Subgrave,
        Fixture::Rock,
        Fixture::Electronic,
        Fixture::Percussion,
        Fixture::Antiphase,
    ]
}

fn sample(fixture: Fixture, index: usize, frame: usize) -> f32 {
    let t = (frame * FRAME_SIZE + index) as f32 / SAMPLE_RATE;
    let tau = 2.0 * std::f32::consts::PI;
    match fixture {
        Fixture::Tone => (tau * 1_000.0 * t).sin() * 0.5,
        Fixture::Sweep => {
            let frequency = 20.0 + 480.0 * ((t / 4.0) % 1.0);
            (tau * frequency * t).sin() * 0.5
        }
        Fixture::PinkNoise => {
            // Deterministic filtered noise: no RNG dependency in the harness.
            let mut x = (index as u32)
                .wrapping_mul(1_664_525)
                .wrapping_add((frame as u32).wrapping_mul(1_013_904_223));
            x ^= x >> 13;
            x ^= x << 17;
            x ^= x >> 5;
            let white = (x as f32 / u32::MAX as f32) * 2.0 - 1.0;
            white * (0.35 + 0.15 * (tau * 80.0 * t).sin().abs())
        }
        Fixture::Subgrave => (tau * 32.0 * t).sin() * 0.7,
        Fixture::Rock => {
            let kick = (tau * 90.0 * t).sin() * (tau * 2.0 * t).sin().abs();
            let guitar = (tau * 440.0 * t).sin() * 0.18;
            (kick * 0.6 + guitar).clamp(-1.0, 1.0)
        }
        Fixture::Electronic => {
            let bass = (tau * 55.0 * t).sin() * 0.5;
            let lead = (tau * 880.0 * t).sin() * 0.15;
            let hat = (tau * 7_000.0 * t).sin() * 0.08;
            bass + lead + hat
        }
        Fixture::Percussion => {
            let phase = (t * 4.0) % 1.0;
            let envelope = (-phase * 18.0).exp();
            envelope * (tau * 120.0 * t).sin() * 0.9
        }
        Fixture::Antiphase => (tau * 220.0 * t).sin() * 0.5,
    }
}

fn percentile(sorted: &[u128], p: f64) -> u128 {
    let index = ((sorted.len().saturating_sub(1)) as f64 * p).round() as usize;
    sorted[index]
}

fn main() {
    let iterations = env::args()
        .skip_while(|arg| arg != "--iterations")
        .nth(1)
        .and_then(|value| value.parse().ok())
        .unwrap_or(DEFAULT_ITERATIONS);

    println!("# echo-dsp-offline-benchmark");
    println!("# sample_rate_hz={SAMPLE_RATE} frame_size={FRAME_SIZE} iterations={iterations}");
    println!("fixture,iterations,Lc_p50_us,Lc_p95_us,Lc_p99_us,frames,drops,overflows,underflows,sequence_ok");

    for fixture in fixtures() {
        let settings = DspSettings {
            sample_rate: SAMPLE_RATE as u32,
            frame_size: FRAME_SIZE,
            band_count: 32,
            band_scale: BandScale::Logarithmic,
            ..DspSettings::default()
        };
        let mut processor = DspProcessor::new(settings).expect("valid benchmark settings");
        let mut output = ProcessedFrame::with_band_count(32);
        let mut samples = vec![0.0_f32; FRAME_SIZE];
        let warmup = 100.min(iterations / 2);
        for frame in 0..warmup {
            for (index, value) in samples.iter_mut().enumerate() {
                *value = sample(fixture, index, frame);
            }
            processor
                .process_into(&samples, &mut output)
                .expect("frame length");
        }

        let mut elapsed = Vec::with_capacity(iterations.saturating_sub(warmup));
        for frame in warmup..iterations {
            for (index, value) in samples.iter_mut().enumerate() {
                *value = sample(fixture, index, frame);
            }
            let start = Instant::now();
            processor
                .process_into(&samples, &mut output)
                .expect("frame length");
            elapsed.push(start.elapsed().as_nanos());
        }
        elapsed.sort_unstable();
        let count = elapsed.len();
        let p50 = percentile(&elapsed, 0.50) / 1_000;
        let p95 = percentile(&elapsed, 0.95) / 1_000;
        let p99 = percentile(&elapsed, 0.99) / 1_000;
        // This harness is single producer/consumer and has no transport queue;
        // the explicit counters make that limitation visible in the report.
        println!(
            "{},{},{},{},{},{},0,0,0,{}",
            fixture.name(),
            count,
            p50,
            p95,
            p99,
            count,
            count
        );
    }
}
