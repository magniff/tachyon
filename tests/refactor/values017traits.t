## (0.17) fix --values on trait methods: a method of the program's trait
## changes in the declaration and in every impl together (`&mut Self` when
## one impl writes: Counter::tick), and the calls follow (bump, twice);
## an impl of a trait that declares `&Self` (std's Ord, Eq; Display with
## `&mut Fmt`) is spelled so. The output is the same.
$ --values=off main.tach -o prog
ok: built prog
% ./prog
16 9 shape rect true 10 3 true false $7
$ fix --values
fixed 9 parameters to &mut T, 17 parameters to &T, 4 arguments	main.tach	+24 -23 lines
% cat main.tach
trait Shape {
    fn area(self: &Self) -> i64;
    fn grow(self: &mut Self, by: i64);
    fn name(self: &Self) -> [u8] { "shape" }
    fn same(self: &Self, other: &Self) -> bool;
}

struct Sq { s: i64 }
struct Rect { w: i64, h: i64 }

impl Shape for Sq {
    fn area(self: &Sq) -> i64 { self.s * self.s }
    fn grow(self: &mut Sq, by: i64) { self.s += by; }
    fn same(self: &Sq, other: &Sq) -> bool { self.s == other.s }
}

impl Shape for Rect {
    fn area(self: &Rect) -> i64 { self.w * self.h }
    fn grow(self: &mut Rect, by: i64) { self.w += by; }
    fn name(self: &Rect) -> [u8] { "rect" }
    fn same(self: &Rect, other: &Rect) -> bool { self.w == other.w && self.h == other.h }
}

// One impl writes: the method is `&mut` in the trait and in both impls.
trait Counter { fn tick(self: &mut Self) -> i64; }
struct Fixed { n: i64 }
struct Live { n: i64 }
impl Counter for Fixed { fn tick(self: &mut Fixed) -> i64 { self.n } }
impl Counter for Live { fn tick(self: &mut Live) -> i64 { self.n += 1; self.n } }

// std's Ord and Eq declare `&Self`: their impls are spelled so.
struct Key { k: i64 }
impl Ord for Key { fn cmp(self: &Key, other: &Key) -> i64 { self.k - other.k } }
impl Eq for Key { fn eq(self: &Key, other: &Key) -> bool { self.k == other.k } }

// Display declares `&Self` and `&mut Fmt` (0.18): spelled so too.
struct Money { c: i64 }
impl Display for Money { fn fmt(self: &Money, f: &mut Fmt) { f.write(f"${self.c}"); } }

fn total<T: Shape>(s: &T) -> i64 { s.area() }
fn bump<T: Shape>(s: &mut T) { s.grow(1); }
fn twice<C: Counter>(c: &mut C) -> i64 { c.tick() + c.tick() }

fn main() {
    let mut a = Sq { s: 2 };
    let mut r = Rect { w: 2, h: 3 };
    a.grow(1);
    bump(&mut a);
    bump(&mut r);
    let b = Sq { s: 4 };
    let mut fx = Fixed { n: 5 };
    let mut lv = Live { n: 0 };
    let x = Key { k: 1 };
    let y = Key { k: 2 };
    let m = Money { c: 7 };
    println(
        f"{total(&a)} {total(&r)} {a.name()} {r.name()} {a.same(&b)} {twice(&mut fx)} {twice(&mut lv)} {x < y} {x == y} {m}");
}
$ main.tach -o prog
ok: built prog
% ./prog
16 9 shape rect true 10 3 true false $7
$ fix --values
note fix.none: nothing to fix
