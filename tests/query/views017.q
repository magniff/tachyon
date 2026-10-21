## View summaries (0.17 T3; tests/query/views017/): declared ones with
## the type filter, std's generic results (parametric: by their type),
## stores, a module's functions with --why, and `views:` in def and show.
$ views first_word pick text_of intern count
crate::first_word	views(s) declared
crate::pick	views(toks) declared
crate::text_of	views(*toks) declared
crate::intern	views() stores(word) declared
crate::count	views()
<std::string::Chars as Iterator>::count	views()
$ views Vec::get Vec::as_slice Vec::push
Vec<Tok>::get	views(*self) parametric
Vec<u64>::get	views()
Vec<Vec<u64>>::get	views()
Vec<Tok>::as_slice	views(self) declared
Vec<u64>::as_slice	views(self) declared
Vec<u8>::as_slice	views(self) declared
Vec<Vec<u64>>::as_slice	views(self) declared
Vec<[u8]>::push	views() stores(x) declared
Vec<Tok>::push	views() stores(x) declared
Vec<u8>::push	views()
Vec<u64>::push	views()
Vec<Vec<u64>>::push	views()
Vec<i64>::push	views()
Vec<u32>::push	views()
Vec<(i64, u32)>::push	views()
Vec<str>::push	views()
Vec<Path>::push	views()
Vec<Result<DirEntry, Error>>::push	views()
$ views crate --why
crate::first_word	views(s) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
crate::pick	views(toks) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
crate::text_of	views(*toks) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
crate::intern	views() stores(word) declared
  why: declared (#[views], #[stores]): callers use the declaration, and the body is checked against it
$ def pick intern count
crate::pick	views017/main.tach:16:4	fn	fn pick(toks: &Vec<Tok>, counts: &Vec<i64>) -> [Tok]	effects: none	views: views(toks) declared
crate::intern	views017/main.tach:27:4	fn	fn intern(names: &mut Vec<[u8]>, word: [u8])	effects: alloc(Gpa) panic	views: views() stores(word) declared
crate::count	views017/main.tach:31:4	fn	fn count(toks: &Vec<Tok>) -> i64	effects: none
std::iter::Iterator::count	../../compiler/std/iter.tach:73:8	trait-method	fn count(self: Self) -> i64
<std::string::Chars as Iterator>::count	../../compiler/std/string.tach:752:8	method	fn count(self: Chars) -> i64	effects: panic diverge
$ views nothing_here
error query.no-match: no definition 'nothing_here'
try: tachyonc query items
[exit 1]
