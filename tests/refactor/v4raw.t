## (0.18.1, V4) Every `*T` is raw: 0.18.0 code that used a `*T` parameter
## as a borrow gets one error per use, whose try: lines migrate it:
## `fix --values` (the parameters to `&T` / `&mut T`, with their calls; an
## impl to its trait's references), `fix --suggested` (a closure's `*T`
## annotation where the bound wants `&T`), `fix --only unsafe` (what stays
## raw: `s`, indexed, given `c"..."`).
$ check --syntax=mixed
main.tach:6:27: error[unsafe] access to a field through a raw pointer is unsafe: `a` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `a` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: tachyonc fix --values main.tach | try: tachyonc fix --only unsafe main.tach
main.tach:6:37: error[unsafe] access to a field through a raw pointer is unsafe: `a` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `a` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: tachyonc fix --values main.tach | try: tachyonc fix --only unsafe main.tach
main.tach:7:30: error[unsafe] access to a field through a raw pointer is unsafe: `a` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `a` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: tachyonc fix --values main.tach | try: tachyonc fix --only unsafe main.tach
main.tach:7:52: error[unsafe] access to a field through a raw pointer is unsafe: `a` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `a` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: tachyonc fix --values main.tach | try: tachyonc fix --only unsafe main.tach
main.tach:7:60: error[unsafe] access to a field through a raw pointer is unsafe: `a` is a `*T` parameter | help: a `*T` parameter is a raw pointer (0.18.1); a borrow is `&T`, or `&mut T` when written through: make `a` one (the first try: changes such parameters, with their calls), or put this in an `unsafe { ... }` block (the second: what the first keeps raw, a pointer indexed, compared, cast, stored or given to C) | try: tachyonc fix --values main.tach | try: tachyonc fix --only unsafe main.tach
main.tach:11:20: error[type error] 'cmp' does not have the signature trait 'Ord' declares: expected 'fn(Key, Key) -> i64'
main.tach:13:31: error[unsafe] indexing a raw pointer is unsafe | help: `p[0]` is pointer arithmetic; the value p points to is `*p` (`*p = x` writes it), unsafe as well through a raw pointer (not a borrow: a `*T` parameter, a local, a field), so put it in an `unsafe { ... }` block (the try: line wraps every such place) | try: tachyonc fix --only unsafe main.tach
main.tach:22:13: error[own.readonly] 'v.as_slice()', a '[i64]', is read-only where 'inout [i64]' is expected: the callee writes through it | help: pass it inout: '&a[..]', '&v', or an 'inout [T]' parameter passed on as '&s' | try: v.as_mut_slice() | try: tachyonc fix --suggested main.tach
main.tach:22:31: error[type error] closure parameter of type '*i64' where 'i64' is wanted | help: a `*T` is a raw pointer (0.18.1), not a reference: write the parameter's type as the bound's | try: &i64 | try: tachyonc fix --suggested main.tach
main.tach:22:40: error[type error] closure parameter of type '*i64' where 'i64' is wanted | help: a `*T` is a raw pointer (0.18.1), not a reference: write the parameter's type as the bound's | try: &i64 | try: tachyonc fix --suggested main.tach
[exit 1]
$ fix --values --syntax=mixed
fixed 3 suggested fixes, 1 parameter to &mut T, 3 parameters to &T, 2 arguments	main.tach	+6 -6 lines
$ fix --suggested --syntax=mixed
note fix.none: nothing to fix
$ fix --only unsafe --syntax=mixed
fixed 1 unsafe block	main.tach	+1 -1 lines
% cat main.tach
// 0.18.0 code: `*T` parameters used as borrows (the legacy rule).
use std::sort_by;

struct Acc { n: i64, sum: i64 }

fn add(a: &mut Acc, x: i64) { a.n += 1; a.sum += x; }
fn mean(a: &Acc) -> i64 { if a.n == 0 { 0 } else { a.sum / a.n } }

struct Key { k: i64 }

impl Ord for Key { fn cmp(self: &Key, other: &Key) -> i64 { self.k - other.k } }

fn first_byte(s: *u8) -> u8 { unsafe { s[0] } }

fn main(gpa: Gpa) {
    let mut a = Acc { n: 0, sum: 0 };
    add(&mut a, 4);
    add(&mut a, 6);
    let mut v: Vec<i64> = Vec::new_in(gpa);
    v.push(3);
    v.push(1);
    sort_by(v.as_mut_slice(), |x: &i64, y: &i64| *x - *y);
    let k = Key { k: 1 };
    let j = Key { k: 2 };
    println(f"{mean(&a)} {v[0]} {k < j} {first_byte(c"hi")}");
}
## (0.20) Then 0.20's spelling, `fix --only conventions` (its 0.19 input
## read --syntax=mixed): the chain 0.16 -> 0.19 -> 0.20 prints what 0.16 did.
$ fix --only conventions --syntax=mixed
fixed 4 parameters to let, 1 parameter to inout, 1 receiver, 2 '&mut e's to '&e', 1 '&e' to a let, 2 '*r's of accesses, 2 'let mut's / 'mut x's to var	main.tach	+9 -9 lines
$ main.tach -o prog
ok: built prog
% ./prog
5 1 true 104
