## (0.17) An f-string passed straight to println, push_fmt or format_in
## is written in place (no closure, no Interp): its type is still shown
## as an f-string's, the call is still a reference of println, push_fmt
## and format_in, and what its writes do is the call's.
$ type fstring017/main.vl:9:13
Interp<closure(*Fmt) -> () at fstring017/main.vl:9:13>	f"n = {n}"
$ type fstring017/main.vl:10:10
Interp<closure(inout Fmt) -> () at fstring017/main.vl:10:10>	f"n = {n}"
$ type fstring017/main.vl:9:20
i64	n
$ type fstring017/main.vl:12:16
Interp<closure(*Fmt) -> () at fstring017/main.vl:12:16>	f"[{n}]"
$ refs println push_fmt format_in --in fstring017/main.vl
# fstring017/main.vl
1:30	use	crate	->std::fmt::format_in	use std::{Buf, Display, Gpa, format_in, println};
1:41	use	crate	->std::fmt::println	use std::{Buf, Display, Gpa, format_in, println};
4:5	call	show	->std::fmt::println	println(x);
9:5	call	main	->std::fmt::println	println(f"n = {n}");
12:7	call	main	->std::Buf::push_fmt	b.push_fmt(f"[{n}]");
13:13	call	main	->std::fmt::format_in	let t = format_in(f"{n}!", gpa);
14:5	call	main	->std::fmt::println	println(t.as_slice());
$ effects main --why io
crate::main	alloc(Gpa) io global panic diverge
  'println(f"n = {n}")' at fstring017/main.vl:9:5 calls 'std::fmt::println'
  'print_acquire()' at <std>:10738:5 calls 'std::fmt::print_acquire'
  'print_acquire_held()' at <std>:10699:9 calls 'std::fmt::print_acquire_held'
  (no source found)
