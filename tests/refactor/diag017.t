## 0.17: a `mod` line without its file: the error's try: line makes it,
## and edit new-file keeps the `mod` line that is there.
$ check
main.tach:1:5: error[module error] cannot find the file of module 'util' | help: looked for util.tach and util/mod.tach: write the file (`edit new-file` takes its text on stdin) | try: tachyonc edit new-file util.tach main.tach
[exit 1]
$ edit new-file util.tach < $T/inputs/diag017_util.tach
made crate::util	util.tach	+3 -0 lines
% cat main.tach
mod util;

fn main() -> i32 {
    util::twice(2) as i32
}
$ check
ok: 0 errors in main.tach
