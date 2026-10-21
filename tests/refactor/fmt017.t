## tachyonc fmt on the references of 0.17 (tests/refactor/fmt017/): `&T`,
## `&mut T`, `&mut [T]`, `&x`, `&mut x`, and `&&` as a prefix (a reference
## to a reference) tight to its operand, a binary `&&` spaced.
$ fmt --syntax=mixed
formatted	main.tach	+7 -7 lines
% cat main.tach
struct P { x: i64 }
struct Q { r: &mut P, s: &[u8] }

fn bump(p: &mut P, by: i64) { p.x += by; }
fn get(p: &P) -> i64 { p.x }
fn deep(p: &&P) -> i64 { 1 }
fn zero(s: &mut [i64]) { for i in 0..s.len { s[i] = 0; } }

fn main() {
    let mut p = P { x: 1 };
    bump(&mut p, 3);
    let r = &p;
    let mut b = [1, 2, 3];
    zero(&mut b[..]);
    let ok = get(r) > 0 && deep(&r) > 0;
    let q = Q { r: &mut p, s: "x" };
    println(f"{b[0]} {ok} {q.r.x}");
}
$ check --syntax=mixed
ok: 0 errors in main.tach
