// The baseline of the shader compiler's translation bench: naga 29
// (wgsl-in, msl-out), each file translated N times; the median time per
// file, parse + validate + write, with bounds checks like wgslc's
// (Restrict for fixed-size indices, ReadZeroSkipWrite for buffers).
use naga::back::msl;
use naga::proc::{BoundsCheckPolicies, BoundsCheckPolicy};
use std::time::Instant;

fn main() {
    let args: Vec<String> = std::env::args().collect();
    let mut n = 200;
    let mut files = vec![];
    let mut i = 1;
    while i < args.len() {
        if args[i] == "-n" {
            n = args[i + 1].parse().unwrap();
            i += 2;
            continue;
        }
        files.push(args[i].clone());
        i += 1;
    }
    let mut total = 0u128;
    for f in &files {
        let src = std::fs::read_to_string(f).unwrap();
        let mut times = vec![];
        let mut bytes = 0;
        let mut ok = true;
        for _ in 0..n {
            let t0 = Instant::now();
            let module = match naga::front::wgsl::parse_str(&src) {
                Ok(m) => m,
                Err(e) => { eprintln!("{f}: {}", e.emit_to_string(&src)); ok = false; break; }
            };
            let info = match naga::valid::Validator::new(naga::valid::ValidationFlags::all(), naga::valid::Capabilities::all()).validate(&module) {
                Ok(i) => i,
                Err(e) => { eprintln!("{f}: {e:?}"); ok = false; break; }
            };
            let mut opts = msl::Options::default();
            opts.lang_version = (3, 0);
            opts.fake_missing_bindings = true;
            opts.bounds_check_policies = BoundsCheckPolicies {
                index: BoundsCheckPolicy::Restrict,
                buffer: BoundsCheckPolicy::ReadZeroSkipWrite,
                image_load: BoundsCheckPolicy::Restrict,
                binding_array: BoundsCheckPolicy::Unchecked,
            };
            let popts = msl::PipelineOptions::default();
            let out = match msl::write_string(&module, &info, &opts, &popts) {
                Ok((s, _)) => s,
                Err(e) => { eprintln!("{f}: {e:?}"); ok = false; break; }
            };
            times.push(t0.elapsed().as_nanos());
            bytes = out.len();
        }
        if !ok {
            println!("{f}\trejected");
            continue;
        }
        times.sort();
        let med = times[times.len() / 2];
        total += med;
        println!("{f}\t{} bytes in\t{bytes} bytes out\tmedian {:.1} us", src.len(), med as f64 / 1000.0);
    }
    println!("total (sum of medians)\t{:.1} us", total as f64 / 1000.0);
}
