## 0.17: a `mod` line without its file: the error's try: line makes it,
## and edit new-file keeps the `mod` line that is there.
$ check
main.vl:1:5: error[module error] cannot find the file of module 'util' | help: looked for util.vl and util/mod.vl: write the file (`edit new-file` takes its text on stdin) | try: volec edit new-file util.vl main.vl
[exit 1]
$ edit new-file util.vl < $T/inputs/diag017_util.vl
made crate::util	util.vl	+3 -0 lines
% cat main.vl
mod util;

fn main() -> i32 {
    util::twice(2) as i32
}
$ check
ok: 0 errors in main.vl
