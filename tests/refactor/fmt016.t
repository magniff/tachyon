## tachyonc fmt on the syntax of 0.16 (tests/refactor/fmt016/): effect
## attributes and their lists, `effects(...)` bounds, default type
## parameters (a type argument in a default, `Vec< T >`, is one), and a
## long list of type parameters broken after a `,`, its next line indented.
$ fmt
formatted	main.tach	+8 -7 lines
% cat main.tach
extern "C" {
    #[link_name = "write"] #[effects(io)]
    fn out_write(fd: i32, data: *u8, count: u64) -> i64;
}

#[effects(alloc(Gpa, extern), panic,)]
fn grow(v: &mut Vec<i64>) {
    v.push(1);
}

#[sealed] #[scoped]
struct Handle { id: i64 }

struct Pair<T, U = i64> { a: T, b: U }

enum E<T = i64, U = Vec<T>> { A(T), B(U) }

#[pure] #[no_alloc]
fn apply<F: Fn(i64) -> i64 + effects(panic),
    G: Fn(i64) -> i64 + effects()>(f: F, g: G, x: i64) -> i64 {
    f(g(x))
}

trait Shape {
    #[pure] fn area(self: *Self) -> i64;
}

fn main(gpa: Gpa) {
    let mut v: Vec<i64, Gpa> = Vec::new_in(gpa);
    grow(&mut v);
    let p: Pair<i64> = Pair { a: 1, b: 2 };
    println(apply(|x| x + 1, |x| x, p.a) + v.len());
}
$ fmt --check
