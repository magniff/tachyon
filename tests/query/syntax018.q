## The syntax of 0.18 parses (phase 0: clauses, invariants, distinct
## types and test attributes are read and kept, not checked): the items,
## an item shown with its clauses, a distinct type, test functions.
$ items
crate	syntax018/main.tach	14
std	<std>	706
crate::tests	syntax018/main.tach	1
$ show crate::push Stack Percent
// crate::push	syntax018/main.tach:19-27	effects: panic
fn push(s: *Stack, x: i64)
    requires s.len < s.max else "push on a full stack"
    ensures s.len == old(s.len) + 1
{
    unsafe {
        (*s).items[(*s).len] = x;
        (*s).len += 1;
    }
}
// crate::Stack	syntax018/main.tach:10-11
struct Stack { items: [i64; 8], len: i64, max: i64 }
invariant self.len <= self.max else "a stack holds at most max items"
// crate::Percent	syntax018/main.tach:17-17
type Percent = distinct i64 invariant 0 <= self && self <= 100;
$ def NodeId any_id tests::two
crate::NodeId	syntax018/main.tach:16:6	type	type NodeId = distinct i64
crate::any_id	syntax018/main.tach:58:4	fn	fn any_id(n: i64)	effects: none
crate::tests::two	syntax018/main.tach:66:8	fn	fn two()	effects: none
$ refs NodeId
# syntax018/main.tach
16:6	def	type NodeId = distinct i64;
47:15	type	next_id	fn next_id(n: NodeId) -> NodeId requires n >= 0 {
47:26	type	next_id	fn next_id(n: NodeId) -> NodeId requires n >= 0 {
78:13	type	main	let id: NodeId = 11;
