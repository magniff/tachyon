## The effects inferred (0.16 T1; tests/query/effects016/): a source of
## each effect, C's table and declarations, unknown C and its callbacks,
## recursion, counted loops and in-bounds indexes, allocators (the
## encapsulation rule, instances with different A, a scope's discharge),
## closures and fn values (closed world).
$ effects putchar malloc labs qsort mystery ext_pure
crate::putchar	io
crate::malloc	alloc(extern)
std::malloc	alloc(extern)
crate::labs	none
crate::qsort	alloc(extern) io global panic diverge
crate::mystery	io
crate::ext_pure	none
$ effects add bump address at part whole color sum same spin forever fact even odd
crate::add	none
crate::bump	global
crate::address	global
crate::at	panic
crate::part	panic
crate::whole	none
crate::color	panic
std::gpu::PassDesc::color	none
crate::sum	none
crate::same	panic
crate::spin	diverge
crate::forever	diverge
crate::fact	diverge
crate::even	diverge
crate::odd	diverge
$ effects deref raw_index trusted calls_c declared heap out by_c sorter main t0
crate::deref	unsafe
crate::raw_index	unsafe
crate::trusted	unsafe
crate::calls_c	unsafe
crate::declared	io unsafe
crate::heap	alloc(extern) unsafe
crate::out	io unsafe
crate::by_c	global
crate::sorter	alloc(extern) io global panic diverge unsafe
crate::main	alloc(extern) io global panic diverge unsafe
crate::t0	none
$ effects Bump::try_alloc Bump::try_resize fill in_scope apply double shout hof allocators
<crate::Bump as Allocator>::try_alloc	unsafe
<crate::Bump as Allocator>::try_resize	alloc(Bump) unsafe
fill<Gpa>	alloc(Gpa) panic
fill<Bump>	alloc(Bump) panic
crate::in_scope	alloc(Arena) panic
crate::apply	io
crate::double	none
crate::shout	io
hof<closure(i64) -> i64 at effects016/main.tach:133:9>	none
hof<closure(i64) -> i64 at effects016/main.tach:133:29>	io
crate::allocators	alloc(Gpa, Bump) io panic
