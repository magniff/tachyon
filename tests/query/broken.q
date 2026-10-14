# A program with errors (broken/): a missing module file, a type error, a
# syntax error and an unknown name. What the front end got to answers;
# the errors are printed only when no definition answers.
$ def good
crate::good  broken/main.tach:7:4  fn  fn good(x: i64) -> i64
$ refs good
broken/main.tach:7:4  def  |  fn good(x: i64) -> i64 {
broken/main.tach:13:5  in crate::bad_types  |  good(2)
broken/main.tach:26:5  in crate::main  |  good(1) as i32
$ refs util::twice
broken/main.tach:8:11  in crate::good  |  util::twice(x) + 1
broken/util.tach:1:8  def  |  pub fn twice(x: i64) -> i64 {
$ show bad_syntax
// crate::bad_syntax  broken/main.tach:16-19
fn bad_syntax() -> i64 {
    let x = (1 + ;
    good(x)
}
$ items
crate  broken/main.tach  7 items
crate::util  broken/util.tach  1 item
$ refs nowhere
tachyonc query: no definition named 'nowhere'
error[module error]: cannot find the file of module 'missing'
 --> broken/main.tach: line 5, column 5
  = help: looked for broken/missing.tach and broken/missing/mod.tach
error[type error]: expected 'bool', got 'i64'
 --> broken/main.tach: line 12, column 19
error[parser error]: expected expression, got ';'
 --> broken/main.tach: line 17, column 18
error[type error]: undefined variable 'nowhere'
 --> broken/main.tach: line 22, column 5
[exit 1]
