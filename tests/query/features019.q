## query features: a function's requirement, inferred or declared, with
## -C target-cpu=generic (crc not in the build); --why: the calls.
$ features hw twice declared guarded main -C target-cpu=generic
crate::hw	crc (inferred)
crate::twice	crc (inferred)
crate::declared	crc (declared)
crate::guarded	none
crate::main	none
$ features twice --why crc -C target-cpu=generic
crate::twice	crc (inferred)
  features019/main.tach:11:5: calls 'hw'
  features019/main.tach:7:5: calls 'std::arch::aarch64::__crc32cd', which needs crc
$ features twice declared -C target-cpu=apple-m1
crate::twice	none
crate::declared	none (declared: crc)
$ features twice --why avx-2
error query.usage: unknown feature 'avx-2' for --why (`tachyonc explain arch.feature_name` lists them)
[exit 2]
## def, show and context print what a function needs beyond the build's
## features after its effects (nothing when it needs nothing).
$ def hw twice declared guarded -C target-cpu=generic
crate::hw	features019/main.tach:6:4	fn	fn hw(c: u32, x: u64) -> u32	effects: none	features: crc (inferred)
crate::twice	features019/main.tach:10:4	fn	fn twice(c: u32) -> u32	effects: none	features: crc (inferred)
crate::declared	features019/main.tach:15:4	fn	fn declared(c: u32) -> u32	effects: none	features: crc (declared)
crate::guarded	features019/main.tach:19:4	fn	fn guarded(c: u32) -> u32	effects: none
$ show declared -C target-cpu=generic
// crate::declared	features019/main.tach:14-17	effects: none	features: crc (declared)
#[target_feature(enable = "crc")]
fn declared(c: u32) -> u32 {
    hw(c, 3)
}
