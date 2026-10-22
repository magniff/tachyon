## A program with errors (broken/): a missing module file, a type error, a
## syntax error and an unknown name. What the front end got to answers,
## with a warning that counts the errors (and names the first when
## nothing answers).
$ def good
crate::good	broken/main.vl:7:4	fn	fn good(x: i64) -> i64	effects: none
warning query.program-errors: 5 errors in the program; results may be incomplete
try: volec --diagnostics=short broken/main.vl -c -o /dev/null
$ refs good
# broken/main.vl
7:4	def	fn good(x: i64) -> i64 {
13:5	call	bad_types	good(2)
24:13	call	bad_later	let y = good(4);
26:5	call	bad_later	good(z) + y
34:5	call	main	good(1) as i32
warning query.program-errors: 5 errors in the program; results may be incomplete
try: volec --diagnostics=short broken/main.vl -c -o /dev/null
$ refs util::twice
# broken/main.vl
8:11	call	good	util::twice(x) + 1
# broken/util.vl
1:8	def	pub fn twice(x: i64) -> i64 {
warning query.program-errors: 5 errors in the program; results may be incomplete
try: volec --diagnostics=short broken/main.vl -c -o /dev/null
$ show bad_syntax
// crate::bad_syntax	broken/main.vl:16-19
fn bad_syntax() -> i64 {
    let x = (1 + ;
    good(x)
}
warning query.program-errors: 5 errors in the program; results may be incomplete
try: volec --diagnostics=short broken/main.vl -c -o /dev/null
$ items
crate	broken/main.vl	8
crate::util	broken/util.vl	1
warning query.program-errors: 5 errors in the program; results may be incomplete
try: volec --diagnostics=short broken/main.vl -c -o /dev/null
$ refs nowhere
error query.no-match: no definition 'nowhere'
try: volec query items
warning query.program-errors: 5 errors in the program; results may be incomplete; first: broken/main.vl:5:5: error[module error] cannot find the file of module 'missing'
try: volec --diagnostics=short broken/main.vl -c -o /dev/null
[exit 1]
