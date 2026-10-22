## 0.17: struct-like variants through the tools: query, refactor variant
## (an arm `Cmd::Jump { .. }` for a new struct-like variant), rename.
$ query show Cmd::Move
// crate::Cmd::Move	main.vl:2-2
    Move { x: i64, y: i64 },
$ query refs Cmd::Move
# main.vl
2:5	def	Move { x: i64, y: i64 },
8:14	pat	run	Cmd::Move { x, y } => x + y,
14:18	init	main	let c = Cmd::Move { y: 2, x: 1 };
15:17	pat	main	if let Cmd::Move { x, .. } = c {
$ refactor variant Cmd --add 'Jump { h: i64 }' --arm '-1'
added variant Jump { h: i64 } to crate::Cmd, an arm in 1 match	main.vl	+2 -0 lines
% cat main.vl
enum Cmd {
    Move { x: i64, y: i64 },
    Quit,
    Jump { h: i64 },
}

fn run(c: Cmd) -> i64 {
    match c {
        Cmd::Move { x, y } => x + y,
        Cmd::Quit => 0,
        Cmd::Jump { .. } => -1,
    }
}

fn main() -> i32 {
    let c = Cmd::Move { y: 2, x: 1 };
    if let Cmd::Move { x, .. } = c {
        println(f"{x}");
    }
    run(c) as i32
}
$ refactor rename Cmd::Move Go
renamed crate::Cmd::Move to Go	main.vl	+4 -4 lines
$ check
ok: 0 errors in main.vl
$ query type main.vl:16:13
Cmd	Cmd::Go { y: 2, x: 1 }
