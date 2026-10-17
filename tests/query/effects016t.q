## `query effects` (0.16 T5): a module's functions, --has, --why, the
## effects column of def, show and context (left out for a set the front
## end could not infer: front/effects/ infers them, 0.16 T1), and the
## errors. (On syntax016/'s program.)
$ effects crate syntax016/main.tach
crate::out_write	io
crate::labs	none
<crate::Square as Shape>::area	none
apply<closure(i64) -> i64 at syntax016/main.tach:47:32>	none
crate::grow	alloc(Gpa) panic
crate::main	alloc(Gpa) io global panic unsafe
$ effects crate --has io syntax016/main.tach
crate::out_write	io
crate::main	alloc(Gpa) io global panic unsafe
$ effects grow --why alloc syntax016/main.tach
crate::grow	alloc(Gpa) panic
  'v.push(1)' at syntax016/main.tach:39:5 grows a Vec<i64>
  'self.reserve_more(1)' at <std>:275:37 grows a Vec<i64>
  'self.alloc.try_resize(self.ptr as *u8, self...' at <std>:221:13 allocates from Gpa (an Allocator method)
$ effects grow --why 'alloc(Arena)' syntax016/main.tach
crate::grow	alloc(Gpa) panic
  (not: alloc(Arena))
$ effects grow --has allocates syntax016/main.tach
error query.usage: unknown effect 'allocates' (effects: alloc, alloc(T), io, global, panic, diverge, unsafe, none)
[exit 2]
$ effects Pair syntax016/main.tach
note query.empty: no function among the names
[exit 1]
$ def grow syntax016/main.tach
crate::grow	syntax016/main.tach:38:4	fn	fn grow(v: &mut Vec<i64>)	effects: alloc(Gpa) panic
