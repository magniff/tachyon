## std from a program that does not use it (0.15): by path, by a name
## the program does not define, its source by `std`, grep in it, a
## show with the `use` line a program needs.
$ def std::read_line Vec::push
std::io::read_line	../../compiler/std/io.tach:40:8	fn	pub fn read_line<A: Allocator>(line: inout Buf<A>) -> std::Result<bool, IoError>
std::Vec::push	../../compiler/std/std.tach:280:12	method	pub fn push(inout self, x: sink T)
$ def read_line twice
std::io::read_line	../../compiler/std/io.tach:40:8	fn	pub fn read_line<A: Allocator>(line: inout Buf<A>) -> std::Result<bool, IoError>
std::io::buffered::BufReader::read_line	../../compiler/std/io/buffered.tach:152:12	method	pub fn read_line<A: Allocator>(inout self, s: inout String<A>) -> Result<i64>
crate::twice	nostd/main.tach:4:4	fn	fn twice(x: i64) -> i64	effects: none
$ show std::print_int
// std::fmt::print_int	../../compiler/std/fmt.tach:31-39	effects: io global panic
// use std::print_int;
#[inline(never)]
pub fn print_int(v: i64) {
    var f = Fmt::to_fd(1);
    // (decimal only: not Fmt::int, whose hex and binary every program
    // using print_int would compile)
    let negative = v < 0;
    fmt_decimal(&f, if negative { (-(v + 1)) as u64 + 1 } else { v as u64 }, negative);
    f.flush();
}
$ text std:1-2
// std:1-2
1	// The standard library (0.5): the module `std`, built into the compiler
2	// (compiler/std/embed.sh makes compiler/src/front/stdsrc.tach from this file
$ grep 'pub fn read_line' --in std
# <std>
9980:1	code	std::io	pub fn read_line<A: Allocator>(line: inout Buf<A>) -> std::Result<bool, IoError> {
10387:5	code	std::io::buffered	pub fn read_line<A: Allocator>(inout self, s: inout String<A>) -> Result<i64> {
$ def no_such_name
error query.no-match: no definition 'no_such_name'
try: tachyonc query items
[exit 1]
