## (0.17) An f-string passed straight to println, push_fmt or format_in
## is written in place (no closure, no Interp): its type is still shown
## as an f-string's, the call is still a reference of println, push_fmt
## and format_in, and what its writes do is the call's.
$ type fstring017/main.tach:9:13
Interp<closure(*Fmt) -> () at fstring017/main.tach:9:13>	f"n = {n}"
$ type fstring017/main.tach:10:10
Interp<closure(*Fmt) -> () at fstring017/main.tach:10:10>	f"n = {n}"
$ type fstring017/main.tach:9:20
i64	n
$ type fstring017/main.tach:12:16
Interp<closure(*Fmt) -> () at fstring017/main.tach:12:16>	f"[{n}]"
$ refs println push_fmt format_in --in fstring017/main.tach
# fstring017/main.tach
1:30	use	crate	->std::format_in	use std::{Buf, Display, Gpa, format_in, println};
1:41	use	crate	->std::println	use std::{Buf, Display, Gpa, format_in, println};
4:5	call	show	->std::println	println(x);
9:5	call	main	->std::println	println(f"n = {n}");
12:7	call	main	->std::Buf::push_fmt	b.push_fmt(f"[{n}]");
13:13	call	main	->std::format_in	let t = format_in(f"{n}!", gpa);
14:5	call	main	->std::println	println(t.as_slice());
$ effects main --why io
crate::main	alloc(Gpa) io global panic diverge
  'println(f"n = {n}")' at fstring017/main.tach:9:5 calls 'std::println'
  'fmt_str(self, s)' at <std>:2811:9 calls 'std::fmt_str'
  'fmt_str_fd(f.fd, s)' at <std>:2710:9 calls 'std::fmt_str_fd'
  'fmt_flush()' at <std>:2726:9 calls 'std::fmt_flush'
  'write(FMT_FD, rest.ptr, rest.len as u64)' at <std>:2647:26 calls C's 'write'
