## View summaries (0.17 T3; tests/query/views017/): declared ones with
## the type filter, std's generic results (parametric: by their type),
## stores, a module's functions with --why, and `views:` in def and show.
$ views first_word pick text_of intern count
crate::first_word	views(s) declared
crate::pick	views(toks) declared
crate::text_of	views(*toks) declared
crate::intern	views() stores(word) declared
std::gpu::wgsl::ir::Module::intern	views() inferred
std::gpu::wgsl::msl::W::intern	views() inferred
crate::count	views()
<std::objc::Ref as NSArrayMethods>::count	views()
<std::string::Chars as Iterator>::count	views()
$ views Vec::get Vec::as_slice Vec::push
Vec<Tok>::get	views(*self) parametric
Vec<u64>::get	views()
Vec<Vec<u64>>::get	views()
Vec<Tok>::as_slice	views(self) declared
Vec<u64>::as_slice	views(self) declared
Vec<[i64; 2]>::as_slice	views(self) declared
Vec<Binding>::as_slice	views(self) declared
Vec<VertexInput>::as_slice	views(self) declared
Vec<ShaderEntry>::as_slice	views(self) declared
Vec<EntryPoint>::as_slice	views(self) declared
Vec<Type, ScopedArena>::as_slice	views(self) declared
Vec<StructMember, ScopedArena>::as_slice	views(self) declared
Vec<i64, ScopedArena>::as_slice	views(self) declared
Vec<Block, ScopedArena>::as_slice	views(self) declared
Vec<Function, ScopedArena>::as_slice	views(self) declared
Vec<Param, ScopedArena>::as_slice	views(self) declared
Vec<u8, ScopedArena>::as_slice	views(self) declared
Vec<[u8], ScopedArena>::as_slice	views(self) declared
Vec<Global, ScopedArena>::as_slice	views(self) declared
Vec<Decl, ScopedArena>::as_slice	views(self) declared
Vec<Expr, ScopedArena>::as_slice	views(self) declared
Vec<Entry, ScopedArena>::as_slice	views(self) declared
Vec<Stmt, ScopedArena>::as_slice	views(self) declared
Vec<Case, ScopedArena>::as_slice	views(self) declared
Vec<ScopeEntry, ScopedArena>::as_slice	views(self) declared
Vec<Val, ScopedArena>::as_slice	views(self) declared
Vec<Local, ScopedArena>::as_slice	views(self) declared
Vec<Fact, ScopedArena>::as_slice	views(self) declared
Vec<Vec<bool, ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<bool, ScopedArena>::as_slice	views(self) declared
Vec<Nm, ScopedArena>::as_slice	views(self) declared
Vec<EntryInfo>::as_slice	views(self) declared
Vec<BindingInfo>::as_slice	views(self) declared
Vec<JobBuffer, ScopedArena>::as_slice	views(self) declared
Vec<u32, ScopedArena>::as_slice	views(self) declared
Vec<JobTexture, ScopedArena>::as_slice	views(self) declared
Vec<FnInfo, ScopedArena>::as_slice	views(self) declared
Vec<Vec<u32, ScopedArena>, ScopedArena>::as_slice	views(self) declared
Vec<Frame, ScopedArena>::as_slice	views(self) declared
Vec<Inv, ScopedArena>::as_slice	views(self) declared
Vec<Ctl, ScopedArena>::as_slice	views(self) declared
Vec<i64>::as_slice	views(self) declared
Vec<u8>::as_slice	views(self) declared
Vec<Vec<u64>>::as_slice	views(self) declared
Vec<Adapter, ScopedArena>::as_slice	views(self) declared
Vec<[u8]>::push	views() stores(x) declared
Vec<Tok>::push	views() stores(x) declared
Vec<u8>::push	views()
Vec<u64>::push	views()
Vec<Vec<u64>>::push	views()
Vec<Adapter>::push	views()
Vec<ShaderEntry>::push	views()
Vec<EntryPoint>::push	views() stores(x) declared
Vec<Binding>::push	views()
Vec<VertexInput>::push	views()
Vec<[i64; 2]>::push	views()
Vec<Type, ScopedArena>::push	views() stores(x) declared
Vec<Expr, ScopedArena>::push	views() stores(x) declared
Vec<[u8], ScopedArena>::push	views() stores(x) declared
Vec<Stmt, ScopedArena>::push	views() stores(x) declared
Vec<i64, ScopedArena>::push	views() stores(x) declared
Vec<Block, ScopedArena>::push	views() stores(x) declared
Vec<u8, ScopedArena>::push	views() stores(x) declared
Vec<Decl, ScopedArena>::push	views() stores(x) declared
Vec<Function, ScopedArena>::push	views() stores(x) declared
Vec<StructMember, ScopedArena>::push	views() stores(x) declared
Vec<Global, ScopedArena>::push	views() stores(x) declared
Vec<Param, ScopedArena>::push	views() stores(x) declared
Vec<Entry, ScopedArena>::push	views() stores(x) declared
Vec<ScopeEntry, ScopedArena>::push	views() stores(x) declared
Vec<Local, ScopedArena>::push	views() stores(x) declared
Vec<Case, ScopedArena>::push	views() stores(x) declared
Vec<Val, ScopedArena>::push	views() stores(x) declared
Vec<Fact, ScopedArena>::push	views() stores(x) declared
Vec<Nm, ScopedArena>::push	views() stores(x) declared
Vec<Vec<bool, ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<bool, ScopedArena>::push	views() stores(x) declared
Vec<FnInfo, ScopedArena>::push	views() stores(x) declared
Vec<Vec<u32, ScopedArena>, ScopedArena>::push	views() stores(x) declared
Vec<u32, ScopedArena>::push	views() stores(x) declared
Vec<Frame, ScopedArena>::push	views() stores(x) declared
Vec<Ctl, ScopedArena>::push	views() stores(x) declared
Vec<Inv, ScopedArena>::push	views() stores(x) declared
Vec<JobTexture, ScopedArena>::push	views() stores(x) declared
Vec<JobBuffer, ScopedArena>::push	views() stores(x) declared
Vec<EntryInfo>::push	views()
Vec<InputInfo>::push	views()
Vec<i64>::push	views()
Vec<BindingInfo>::push	views()
Vec<u32>::push	views()
Vec<Adapter, ScopedArena>::push	views() stores(x) declared
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
crate::pick	views017/main.tach:16:4	fn	fn pick(toks: Vec<Tok>, counts: Vec<i64>) -> [Tok]	effects: none	views: views(toks) declared
crate::intern	views017/main.tach:27:4	fn	fn intern(names: inout Vec<[u8]>, word: [u8])	effects: alloc(Gpa) panic	views: views() stores(word) declared
std::gpu::wgsl::ir::Module::intern	../../compiler/std/gpu/wgsl/ir.tach:528:12	method	pub fn intern(inout self, kind: u8, sk: u8, n: i64, mm: i64, base: i64, space: u8, access: u8) -> i64	effects: alloc(ScopedArena) panic
std::gpu::wgsl::msl::W::intern	../../compiler/std/gpu/wgsl/msl.tach:242:8	method	fn intern(inout self, s: [u8]) -> Nm	effects: alloc(ScopedArena) panic
crate::count	views017/main.tach:31:4	fn	fn count(toks: Vec<Tok>) -> i64	effects: none
std::iter::Iterator::count	../../compiler/std/iter.tach:73:8	trait-method	fn count(self) -> i64
std::objc::foundation::NSArrayMethods::count	../../compiler/std/objc/foundation.tach:304:8	trait-method	fn count(self) -> u64
<std::objc::Ref as NSArrayMethods>::count	../../compiler/std/objc/foundation.tach:310:8	method	fn count(self) -> u64	effects: alloc(extern) io global panic diverge unsafe
<std::string::Chars as Iterator>::count	../../compiler/std/string.tach:753:8	method	fn count(self) -> i64	effects: panic diverge
$ views nothing_here
error query.no-match: no definition 'nothing_here'
try: tachyonc query items
[exit 1]
