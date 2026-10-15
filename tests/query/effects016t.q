## `query effects` (0.16 T5): a module's functions, --has, --why, the
## effects column of def, show and context (left out for a set the front
## end could not infer: front/effects/ infers them, 0.16 T1), and the
## errors. (On syntax016/'s program.)
$ effects crate syntax016/main.tach
crate::out_write	alloc io global panic diverge unsafe (unknown)
crate::labs	alloc io global panic diverge unsafe (unknown)
<crate::Square as Shape>::area	alloc io global panic diverge unsafe (unknown)
apply<closure(i64) -> i64 at syntax016/main.tach:47:32>	alloc io global panic diverge unsafe (unknown)
crate::grow	alloc io global panic diverge unsafe (unknown)
crate::main	alloc io global panic diverge unsafe (unknown)
$ effects crate --has io syntax016/main.tach
crate::out_write	alloc io global panic diverge unsafe (unknown)
crate::labs	alloc io global panic diverge unsafe (unknown)
<crate::Square as Shape>::area	alloc io global panic diverge unsafe (unknown)
apply<closure(i64) -> i64 at syntax016/main.tach:47:32>	alloc io global panic diverge unsafe (unknown)
crate::grow	alloc io global panic diverge unsafe (unknown)
crate::main	alloc io global panic diverge unsafe (unknown)
$ effects grow --why alloc syntax016/main.tach
crate::grow	alloc io global panic diverge unsafe (unknown)
  (effects are not inferred yet: 0.16 T1)
$ effects grow --why 'alloc(Arena)' syntax016/main.tach
crate::grow	alloc io global panic diverge unsafe (unknown)
  (not: alloc(Arena))
$ effects grow --has allocates syntax016/main.tach
error query.usage: unknown effect 'allocates' (effects: alloc, alloc(T), io, global, panic, diverge, unsafe, none)
[exit 2]
$ effects Pair syntax016/main.tach
note query.empty: no function among the names
[exit 1]
$ def grow syntax016/main.tach
crate::grow	syntax016/main.tach:38:4	fn	fn grow(v: *Vec<i64>)
