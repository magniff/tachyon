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
