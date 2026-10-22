# Here

This copy has no release tags and no bootstrap cache, so:

- build the compiler with `bootstrap/eval-build.sh` (instead of
  `bootstrap/bootstrap.sh --dev`): the previous release
  (`target/builder/volec`) compiles `compiler/src`, the result
  compiles it twice more, the two outputs must be identical, and the
  compiler lands in `target/volec` (about 20-40 s; `--quick` skips
  the third build);
- do not run `bootstrap/bootstrap.sh` or `bootstrap/gate.sh`: they need
  the tags. Test with `tests/run.sh FILTER` (cases whose name contains
  FILTER; the whole suite takes several minutes);
- there is no need to commit: your working tree is what is graded. The
  grading builds it as `bootstrap/eval-build.sh` does (the fixpoint
  included), runs the test filters the task names and hidden tests of
  its own.
