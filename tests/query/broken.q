## A program with errors (broken/): a missing module file, a type error, a
## syntax error and an unknown name. What the front end got to answers,
## with a warning that counts the errors (and names the first when
## nothing answers).
$ def good
crate::good	broken/main.tach:7:4	fn	fn good(x: i64) -> i64
warning query.program-errors: 4 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
$ refs good
# broken/main.tach
7:4	def	fn good(x: i64) -> i64 {
13:5	bad_types	good(2)
26:5	main	good(1) as i32
warning query.program-errors: 4 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
$ refs util::twice
# broken/main.tach
8:11	good	util::twice(x) + 1
# broken/util.tach
1:8	def	pub fn twice(x: i64) -> i64 {
warning query.program-errors: 4 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
$ show bad_syntax
// crate::bad_syntax	broken/main.tach:16-19
fn bad_syntax() -> i64 {
    let x = (1 + ;
    good(x)
}
warning query.program-errors: 4 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
$ items
crate	broken/main.tach	7
crate::util	broken/util.tach	1
warning query.program-errors: 4 errors in the program; results may be incomplete
try: tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
$ refs nowhere
error query.no-match: no definition 'nowhere'
try: tachyonc query items
warning query.program-errors: 4 errors in the program; results may be incomplete; first: broken/main.tach:5:5: error[module error] cannot find the file of module 'missing'
try: tachyonc --diagnostics=short broken/main.tach -c -o /dev/null
[exit 1]
