# Semantics audit before 0.25: views and projections

Branch `sem-views`, against release-0.25 (2476e990). This is a red-team pass:
the goal was to break the rule that a view never outlives what it views and
is never invalidated under it. The rule covers slices, `str` and `Path`,
structs holding views, containers of views, projections, and the
let-as-borrow rule.

**Probes.** 467 probe programs were written, and 434 became regression tests,
`tests/run/sem_views_*.vl`. The 33 dropped probes misused an API, or were
leak-only variants that tests/run cannot observe. Each probe was run through
`volec check`, then at -O0 and -O2 with `--check-alloc`. No probe printed
differently at -O0, -O1 and -O2. The valgrind row was not run, because
`--check-alloc` already confirmed every SOUNDNESS finding: each prints
`use after free: block #N ... freed at ...` or a leak.

**Findings.**

| class | tests (XFAIL) | distinct causes |
|---|---|---|
| SOUNDNESS | 134 | 22 |
| WRONG | 3 | 1 |
| OVERSTRICT | 26 | 14 |
| DIAG | (in the messages below) | 10 |

The common shape of the SOUNDNESS tests is as follows. A `String` s is
viewed (`s.as_str()`), and the view passes through the construct under test
into `r`. Then `s.push_str(<80 bytes>)` reallocates s, and `println(r)` reads
the freed text. Vole should reject the program with `own.conflict`. The test
carries `// ERROR: error[own.conflict]` and `// XFAIL: SOUNDNESS ...`.

## Rules probed, by context

✔ means the rule held, ✘ means a SOUNDNESS finding, ◐ means it held in some
shapes and failed in others (the findings below name which), and — means
the cell was not probed.

| rule \ context | local | field | element (Vec idx / get) | tuple, Option, Result, enum | let param (summary) | inout/sink param | method receiver | generic T | trait method | closure | loop / match / if / `?` | thread (scope/spawn) | temporary |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| a view is invalidated by push / growth of its owner | ✔ | ✔ | ✘ (F1) | ✔ one level, ✘ two (F4) | ✘ (F2) | ✘ stores (F11) | ✘ (F2) | ✔ | ✘ (F2) | ✘ (F8) | ✔ | ✔ (sync.scope_write) | ✘ (F5, F6) |
| ... by reassignment of its owner | ✔ | ✔ | ✔ | ✔ | — | ✘ (F11) | ✔ | — | — | — | ✔ | — | — |
| ... by a move / drop / scope end of its owner | ✔ | ✔ | ✔ | — | — | ✔ (own.escape) | — | — | — | — | ✔ | ✔ (sync.borrow_escapes) | ✘ (F13) |
| a view stored into a container makes it hold the loan | ✔ push/insert | ✔ | ✘ `v[0] = w` (F12) | ✔ | ✘ (F2) | ✘ (F11) | ✔ | ✔ | — | — | ✘ via `match &o` (F12) | — | — |
| exclusivity of inout views and projections | ✔ | ✔ | ✘ receiver through `v[i]` (F14) | — | — | ✔ | ✔ | — | — | ✘ (F9, W1) | ✔ | ✔ | — |
| iterator invalidation | ✔ Vec, String, BTreeMap, HashSet | — | — | — | — | — | — | — | — | — | ✘ HashMap (F16) | — | ✘ (F5, F6) |
| move-only views (inout fields) move | ✘ (F10) | — | — | — | — | ✘ sink | — | — | — | — | — | — | — |
| statics hold only ∅ views | ✘ (F17) | — | ✘ static array | — | ✘ | — | — | — | — | — | — | — | — |
| let-as-borrow: a borrowed let param is immutable, the result views it | ✔ | ✔ nested | — | ✔ Option, tuple, struct | ✔ | ✔ `f(a, &a)` rejected | ✔ `e.mix(&e)` rejected | ✔ | ✔ default methods | ✘ closure param copied (O) | ✔ recursion | — | ✔ fn arg in a loop, ✘ receiver (F13) |
| let-as-borrow vs statics | ✘ (F18) | | | | | | | | | | | | |
| pinned `#[views]` / `#[stores]` checked | ✔ | — | ✘ element level (F19) | — | ✔ | ✔ | ✔ | — | ✔ binds impls | — | — | — | — |
| `-> let T`, `-> inout T`, `Option<inout T>` (D21) | not implemented (O1) | | | | | | | | | | | | |
| `-> inout [T]`, `as_mut_slice`, `get_mut`, `get_or_insert` | ✔ | — | — | — | ✔ own.readonly from let | ✔ | ✔ | — | — | — | ✔ | — | — |
| str / Path views (`as_str`, `trim`, `split_once`, `file_name`, `parent`, DirEntry) | ✔ | ✔ | ✘ (F1) | ✔ | ✔ | — | ✔ | — | — | — | ✔ named iterators | ✔ | ✘ temporary iterators (F5) |

## SOUNDNESS

Each finding gives one representative test (in tests/run), its minimal
repro, and the other shapes, which are in the tests named. All of them are
accepted, and `--check-alloc` reports a use after free (a leak for F20).

- **F1. `v[i]` of a Vec of views drops the element's origin.** This happens
  even with no function involved.
  - Representative: `sem_views_vec_index_local.vl`. Its repro is
    `v.push(b.as_slice()); let r = v[0]; b.push(..)x100; r[0]`.
  - Other shapes: `v.as_slice()[0]`; Vec<[u8]> with a Buf; the guide's own
    parser (`self.toks[self.pos]`, in `sem_views_parser_tokens_owner.vl`);
    `vv[0].as_slice()` with `vv[0].push`.
  - Tests: `sem_views_m_v{d,e,f,g,h}`, `_s_vec_local`, `_sv_sv14_*`,
    `_st_st12g_*`.
- **F2. A function's summary loses views held in its parameters' elements and
  fields.** This is the book writer's finding, and these tests are its
  shapes:
  - Vec, Vec<Vec>, `(Vec<str>, i64)`, Option<Vec>, Result<Vec>, Vec<Option>,
    an enum payload Vec, Vec of structs, a struct holding a Vec;
  - methods and trait methods over such a struct, a generic call of a trait
    method, `impl Trait for Vec<str>`;
  - a sink Vec, nested calls, `l.get(0)`, `l.as_slice()[0]`,
    `l.get(0).split(' ').next()`, `l[0].trim()`, a closure parameter.
  - The stores side has the same gap: `out.push(src[0])` and
    `out = src[0]`.
  - Tests: `sem_views_s_*`, `_g_g_*_fn*`, `_g_g_{opt,res}_vec`, `_g_g_hm_vec`,
    `_g_g_struct_*`, `_g_g_trait_vec`, `_g_g_vec_array`, `_g_g_split`.
- **F4. An element read through two levels of containers with std accessors
  loses its origin**, while one level is caught.
  - Representative: `sem_views_nested_get_local.vl`, with
    `vv.get(0).get(0)`.
  - Other shapes: `m.get(1).unwrap().get(0)` of a HashMap<i64, Vec<str>>,
    `o.unwrap().get(0)`, `l.get(0)[1]` of a Vec<[str; 2]>,
    `vv.last().unwrap().last().unwrap()`, `mk(w, gpa).get(0)` of a returned
    Vec.
- **F5. The item of a temporary text iterator loses its origin.**
  - Representative: `sem_views_str_split_next_temp.vl`, with
    `let r = s.split(' ').next().unwrap()`.
  - Other shapes: split_whitespace, splitn, matches, lines, `.map(..)` over
    them, `p.as_path().components().next()`.
  - A named iterator and a `for` over it are caught.
- **F6. The item of a temporary HashMap iterator loses its origin:**
  `m.values().next()`, `m.keys().next()`, `m.iter().next().unwrap().1`. See
  `sem_views_hashmap_iter_temp.vl`.
- **F7. A Vec collected from views loses their origin:**
  `s.split(' ').collect_in(gpa)`, `v.iter().collect_in(gpa)` and the map form.
  See `sem_views_collect_of_views.vl`.
- **F8. A closure's result loses what its captures hold:** `|| v.get(0)`,
  `|i| v.get(i)`, `|| v[0]`, and `|| s.as_str()` (a view of the captured
  owner). A captured `str` (`|| w`) is caught. See
  `sem_views_closure_returns_element.vl` and
  `sem_views_closure_returns_view_of_capture.vl`.
- **F9. A closure's mutating capture is not exclusive.**
  `var add = |x| v.push(x); let sl = v.as_slice(); add(..); sl[0]` is a use
  after free. See `sem_views_closure_mut_capture_alias.vl`.
- **F10. A move-only view is copied, not moved.** For a struct with an
  `inout` field, `var p2 = p`, `let p2 = p` and `eat(p)` (a sink param) all
  leave p usable. Two exclusive accesses to v are then live, and a slice
  taken through p2 survives p's pushes. See `sem_views_moveonly_copied.vl`.
- **F11. A view stored into an inout parameter is not live to the return.**
  Inside the callee, `out.push(s.as_str()); s.push_str(..)` is accepted. The
  same holds for `inout self` storing into self.list, for
  `out = s.as_str()`, and for `s = String::from_in(..)` afterwards. See
  `sem_views_callee_store_then_grow.vl`.
- **F12. A view stored through a place is not recorded on the container.**
  The places are:
  - `v[0] = w`;
  - `m[0] = w` through `v.as_mut_slice()`;
  - `a[0] = w` through `get_mut`;
  - `inout r = &v; r.push(w)`;
  - `match &o { Some(l) => l.push(w) }`;
  - `vv[0].push(w)` and `v[0].t = w`.

  Arrays, fields and tuples are caught. See
  `sem_views_store_through_place.vl` and `sem_views_sto_*`.
- **F13. A view of a method call's temporary receiver outlives the
  temporary.** In `{ keep = mk(gpa).view(); }` it escapes the block, and the
  same happens in an if branch. In a loop, every pushed view points into the
  same reused slot, which prints "cccc cccc cccc", and a struct-literal
  receiver does the same. A function's temporary argument (`nm(mk(c))`) is
  correctly own.escape. See `sem_views_temp_receiver_escape_{block,loop}.vl`.
- **F14. An inout receiver called through a Vec index place ignores views of
  the element.** In `let w = owners[0].as_str(); owners[0].push_str(..)`,
  w reads freed text. `grow(&owners[0])` and an array's `a[0].push_str` are
  caught. See `sem_views_vec_index_receiver_write.vl`.
- **F15. A view of an accessor's copy of an owned element is tied to the
  copy, not to the container.** The shapes are `v.get(0).as_str()`,
  `v.last().unwrap().as_str()` and `m.get(1).unwrap().as_str()`, followed by
  clear, remove or insert. See `sem_views_accessor_copy_view.vl`.
- **F16. HashMap iterators hold no loan on the map.** The shapes are
  `for k in m.keys() { m.insert(..) }` and the iter/values/remove forms, and
  `var it = m.iter()` kept across inserts. Vec, String, BTreeMap and HashSet
  are caught. See `sem_views_hashmap_iter_invalidation.vl`.
- **F16b. BTreeMap, BTreeSet and HashSet `insert` don't record a stored
  view.** `get` and `first_key_value` of view values lose the origin too.
  See `sem_views_set_btree_insert_holds.vl`.
- **F17. A `static var` holds a view of a String.** This happens directly, in
  a static array, and through a function that stores its parameter. See
  `sem_views_static_holds_view.vl`.
- **F18. The let-as-borrow rule makes a let parameter alias a static that the
  callee writes.** `fn f(a: [i64;4]) -> [i64] { G[0] = 9; a[0..1] }` called
  as `f(G)` prints 9: the immutable parameter changed under the callee. See
  `sem_views_let_borrow_static_alias.vl`.
- **F19. A pinned summary has the same blind spot as inference.**
  `#[views()] fn first(l: Vec<str>) -> str { l.get(0) }` passes the body
  check. See `sem_views_pin_pin07_elem_level_pin.vl`.
- **F20. A temporary Vec, Buf or String used as the receiver of a std method
  is never dropped (a leak).** The shapes are `v.clone().len()`,
  `String::from_in(..).as_str()`, `to_string_in(..).len()`, and
  `Path::new(..).join_in(..).as_path()`. User-type temporaries are dropped.
  See `sem_views_temp_receiver_leak.vl`, which counts drops: 1 where it
  should be 2.

## WRONG

- **W1. A closure's mutating capture doesn't exclude other accesses while
  the closure is live.** Reading `v.len()` between two calls of
  `|x| v.push(x)` is accepted, as is a second mutating closure over v, or
  reading `n` between calls of `|| n += 1`. The cases without a view are
  not UB, but they break the law of exclusivity. See
  `sem_views_cl_cl1{2,3,5}_*`.

## OVERSTRICT

- **O1. Projections (D21) are not implemented.** `-> let T` and `-> inout T`
  give own.escape "references as results come in 0.17.1".
  `Option<inout T>` parses, but its binding is immutable. A `-> let str`
  result is "not Display". See `sem_views_pj_*`, `_m_fc`, `_m_fd` and
  `sem_views_let_str_result_display.vl`.
- **O2. `for inout x in &v` is a parser error** ("'inout' is a keyword ... a
  name cannot be spelled so"). See `sem_views_it_it0{1..4}_*`.
- **O3. The let-as-borrow rule covers results but not stores.**
  `fn keep(out: inout Vec<[u8]>, e: E) { out.push(e.name[..e.len]) }` is
  own.escape, though the decided rule includes stores. See
  `sem_views_l_l8`, `_l_l9`.
- **O4. A closure's let array parameter is copied,** so a view of it is
  own.escape. See `_l_l12`.
- **O5. `apply(|x| nm(x), e)` doesn't satisfy `F: Fn(E) -> [u8]`.** The bound
  becomes `Fn(let E)`. See `_lb_lb08`.
- **O6. A nested `for x in row` keeps a str element, which is reported as
  viewing the internal `__for_seq`.** See `_g_g_vv_for*`.
- **O7. A view of a `for` loop's borrowed owned element kept past the loop is
  own.escape.** It should be a loan on the container. See
  `_st_st13e`, `_it_it05`.
- **O8. `let (_, l) = t` of a let tuple parameter is own.move_out.** It
  should borrow (D13). See `_g_g_tuple_vec`.
- **O9. A view field re-pointed to another owner (`w.s = u.as_slice()`) keeps
  the old loan.** See `_sv_sv16`.
- **O10. A string literal can't go to `thread::spawn`,** though it is a
  static view. See `_th_th08`.
- **O11. `std::swap(&a, &b)` of two `[T]` locals fails inside std,** with
  "expected '*[i64]', got 'inout inout [i64]'". See `_a_a32`.
- **O12. A non-capturing closure given to a `fn(Vec<i64>) -> i64` parameter
  is `unsafe`,** "a closure with pointer parameters". See `_m_fe`.
- **O13. `var r = ""` is `[u8]`,** so assigning a str to it is distinct.mix.
  See `_s_fn_for_assign`.
- **O14. An empty literal for an annotated `var sl: [i64] = []` is "cannot
  infer the type of an empty array".** See `sem_views_empty_slice_literal.vl`.

Strict by design, and not counted:
- a type with Drop cannot hold views (own.drop_view);
- items of borrowing iterators over owned elements are own.move_out;
- `var x = part` of a let parameter is a copy (l15).

## DIAG

- **D1.** own.escape says "'f' returns a reference ('let [u8]'): references
  as results come in 0.17.1". The version is stale, "reference" is a
  Rust-era word, and it says `let [u8]` for `let str`.
- **D2.** `for inout` reports that 'inout' is a keyword used as a name. It
  should say that `for inout` is not there yet.
- **D3.** An own.escape message names the internal `__for_seq`.
- **D4.** own.move_out says "cannot move 't' ... out of a reference", a
  Rust-era word.
- **D5.** own.conflict says "'v' is read while 't' borrows it mutably", Rust's
  words (the inout projection probes).
- **D6.** own.escape for a stored let parameter says "'e' is dropped when
  'keep' returns". A let parameter is not dropped by the callee.
- **D7.** Closure names are spelled in full twice in one message:
  "'closure([u8; 5]) -> [u8] at f.vl:5:13' returns a view of 'x', which is
  dropped when 'closure(...) at ...' returns".
- **D8.** sync.borrow_escapes says "(str is a view ([u8]))".
- **D9.** For an `Option<inout T>` binding, the help is "make it mutable:
  `var r`". The binding is an access, so `var` is the wrong fix.
- **D10.** The std::swap failure (O11) is reported at `<std>:2690` with
  internal types, and gives the user no line of their own.
