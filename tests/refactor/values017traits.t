## (0.17) fix --values on trait methods: a method of the program's trait
## changes in the declaration and in every impl together (`&mut Self` when
## one impl writes: Counter::tick), and the calls follow (bump, twice);
## an impl of a trait that declares `&Self` (std's Ord, Eq; Display with
## `&mut Fmt`) is spelled so. The output is the same.
## (0.18.1, V4: a `*T` parameter is raw, so the program before the fix no
## longer builds; the output after it is the one 0.16's semantics gave,
## recorded here before 0.18.1: `16 9 shape rect true 10 3 true false $7`. What the fix keeps raw is wrapped in
## `unsafe` by `fix --only unsafe`, the second try: of the error.)
$ fix --values
fixed 9 parameters to &mut T, 17 parameters to &T, 2 arguments	main.vl	+22 -22 lines
## (0.20) Then 0.20's spelling, `fix --only conventions` (the migration reads
## 0.19's spelling itself), before the fixes that read 0.20's.
$ fix --only conventions
fixed 6 parameters to let, 3 parameters to inout, 17 receivers, 2 '&mut e's to '&e', 3 '&e's to a let, 4 'let mut's / 'mut x's to var	main.vl	+28 -27 lines
% cat main.vl
trait Shape {
    fn area(self) -> i64;
    fn grow(inout self, by: i64);
    fn name(self) -> [u8] { "shape" }
    fn same(self, other: Self) -> bool;
}

struct Sq { s: i64 }
struct Rect { w: i64, h: i64 }

impl Shape for Sq {
    fn area(self) -> i64 { self.s * self.s }
    fn grow(inout self, by: i64) { self.s += by; }
    fn same(self, other: Sq) -> bool { self.s == other.s }
}

impl Shape for Rect {
    fn area(self) -> i64 { self.w * self.h }
    fn grow(inout self, by: i64) { self.w += by; }
    fn name(self) -> [u8] { "rect" }
    fn same(self, other: Rect) -> bool { self.w == other.w && self.h == other.h }
}

// One impl writes: the method is `&mut` in the trait and in both impls.
trait Counter { fn tick(inout self) -> i64; }
struct Fixed { n: i64 }
struct Live { n: i64 }
impl Counter for Fixed { fn tick(inout self) -> i64 { self.n } }
impl Counter for Live { fn tick(inout self) -> i64 { self.n += 1; self.n } }

// std's Ord and Eq declare `&Self`: their impls are spelled so.
struct Key { k: i64 }
impl Ord for Key { fn cmp(self, other: Key) -> i64 { self.k - other.k } }
impl Eq for Key { fn eq(self, other: Key) -> bool { self.k == other.k } }

// Display declares `&Self` and `&mut Fmt` (0.18): spelled so too.
struct Money { c: i64 }
impl Display for Money { fn fmt(self, f: inout Fmt) { f.write(f"${self.c}"); } }

fn total<T: Shape>(s: T) -> i64 { s.area() }
fn bump<T: Shape>(s: inout T) { s.grow(1); }
fn twice<C: Counter>(c: inout C) -> i64 { c.tick() + c.tick() }

fn main() {
    var a = Sq { s: 2 };
    var r = Rect { w: 2, h: 3 };
    a.grow(1);
    bump(&a);
    bump(&r);
    let b = Sq { s: 4 };
    var fx = Fixed { n: 5 };
    var lv = Live { n: 0 };
    let x = Key { k: 1 };
    let y = Key { k: 2 };
    let m = Money { c: 7 };
    println(
        f"{total(a)} {total(r)} {a.name()} {r.name()} {a.same(b)} {twice(&fx)} {twice(&lv)} {x < y} {x == y} {m}");
}
$ fix --only unsafe
note fix.none: nothing to fix
$ fix --values
note fix.none: nothing to fix
$ main.vl -o prog
ok: built prog
% ./prog
16 9 shape rect true 10 3 true false $7
