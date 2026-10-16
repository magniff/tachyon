## (0.17) fix --values, the migration to references (docs/design/
## value-semantics.md §5): `*T` parameters become `&mut T` when written
## (through a callee too: add_twice), else `&T`; written slices `&mut
## [T]`; owned parameters only read `&T` (total, count, first; keep
## returns its own, so it stays); the calls follow, and the program's
## output is the same. Kept: a raw walk, `**T`, a closure's parameters, a
## function used as a value. (T7: the program before the fix is 0.16
## code, which the default --values=error rejects: it is built with the
## opt-out, 0.16's semantics.)
$ --values=off main.tach -o prog
% ./prog
3 3 0 6 0 0 1 9 12
$ fix --values
fixed 5 parameters to &mut T, 3 parameters to &T, 1 slice parameter to &mut [T], 3 owned parameters to &T (only read), 8 arguments	main.tach	+20 -20 lines
% cat main.tach
struct Stats { count: i64, sum: i64 }
struct Inv { items: Vec<i64>, name: Buf }

fn add(s: &mut Stats, x: i64) { s.count += 1; s.sum += x; }
fn mean(s: &Stats) -> i64 { if s.count == 0 { 0 } else { s.sum / s.count } }
fn add_twice(s: &mut Stats, x: i64) { add(s, x); add(s, x); }
fn show(s: &Stats) -> i64 { mean(s) }
fn push_all(v: &mut Vec<i64>, n: i64) { for i in 0..n { v.push(i); } }
fn total(v: &Vec<i64>) -> i64 { let mut t = 0; for x in v { t += x; } t }
fn count(inv: &Inv) -> i64 { inv.items.len() }
fn keep(v: Vec<i64>) -> Vec<i64> { v }
fn fill(s: &mut [i64], x: i64) { for i in 0..s.len { s[i] = x; } }
fn sum(s: [i64]) -> i64 { let mut t = 0; for x in s { t += x; } t }
fn first(v: &Vec<i64>) -> i64 { v[0] }

impl Stats {
    fn reset(self: &mut Stats) { self.count = 0; self.sum = 0; }
    fn get(self: &Stats) -> i64 { self.sum }
}

fn main(gpa: Gpa) {
    let mut st = Stats { count: 0, sum: 0 };
    add(&mut st, 4);
    add_twice(&mut st, 3);
    let m = show(&st);
    st.reset();
    Stats::get(&st);
    let mut v: Vec<i64> = Vec::new_in(gpa);
    push_all(&mut v, 3);
    let t = total(&v);
    let inv = Inv { items: Vec::new_in(gpa), name: Buf::new_in(gpa) };
    let c = count(&inv);
    let mut a = [0, 0, 0];
    fill(&mut a[..], 2);
    let s = sum(a[..]);
    let w = keep(v);
    let f = first(&w);
    let mut list: Vec<Stats> = Vec::new_in(gpa);
    list.push(Stats { count: 2, sum: 1 });
    list.push(Stats { count: 1, sum: 5 });
    ranked(&mut list);
    let mut x = 1;
    let mut px = &x as *i64;
    set_via(&px, 9);
    let n2 = Node { value: 2, next: 0 as *Node };
    let n1 = Node { value: 1, next: &n2 };
    println(f"{m} {t} {c} {s} {f} {st.get()} {list[0].sum} {x} {walk(&n1)}");
}

// Kept: a raw walk (the copy would be a reference), a pointer to a
// pointer, a closure's parameters (its type is sort_by's), a function
// used as a value.
struct Node { value: i64, next: *Node }

fn walk(n: *Node) -> i64 {
    let mut p = n;
    let mut t = 0;
    while p != 0 as *Node {
        unsafe {
            t = t * 10 + (*p).value;
            p = (*p).next;
        }
    }
    t
}

fn set_via(pp: **i64, v: i64) {
    unsafe { **pp = v; }
}

fn by_rank(a: *Stats, b: *Stats) -> i64 { a.sum - b.sum }

fn ranked(v: &mut Vec<Stats>) {
    sort_by(v.as_slice(), |a: *Stats, b: *Stats| a.count - b.count);
    let f = unsafe { by_rank };
    sort_by(v.as_slice(), f);
}
$ main.tach -o prog
% ./prog
3 3 0 6 0 0 1 9 12
$ fix --values
note fix.none: nothing to fix
$ fix --only values --dry-run
note fix.none: nothing to fix
