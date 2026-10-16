## query items TYPE (0.17): a type's own line and the functions of its
## impl blocks (std's types too: what an unknown method's try: names).
$ items Shape
# crate::Shape	types017/main.tach:3:10
3	enum	pub enum Shape
8	impl	impl Shape
9	method	pub fn area(self: &Shape) -> i64
16	method	pub fn name(self: &Shape) -> [u8]
$ items Nothing
error query.no-match: no module 'Nothing'
try: tachyonc query items
[exit 1]
