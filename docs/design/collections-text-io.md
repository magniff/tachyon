# vole 0.20 design: collections, text and I/O, split so that most of it starts before 0.17

I read the language and std from `/Users/magniff/workspace/vole/.claude/worktrees/design-020` (branch design-020 at night-final 28b1a42: 0.16.0 plus the night's 0.17 familiar forms), using `volec query items std`, `query show` on std's items, `guide std`, `guide rust`, docs/grammar.md ("Additions of 0.17: familiar forms") and docs/roadmap.md (0.16 to 0.23). The designs this one builds on are docs/design/effects-allocation.md (0.16, decided) and docs/design/value-semantics.md on branch design-017b (0.17, Revision 1, decided). The naming evidence is .claude/briefs/research/familiar-names.md. The measurements in §1 were taken on aarch64-macos with this tree's `target/volec -O2` and rustc 1.98 `-O`. I changed nothing outside this file.

The roadmap's 0.20 is three things: collections, text, and I/O with the system, each measured against Rust's std and C. This design fixes what they are (§2), how fast they must be (§3), and how the work splits (§4). The split is the point of the document: 0.17 (value semantics), 0.18 (property tests) and 0.19 (`std::arch`) have not shipped, but about half of 0.20's code does not depend on them. That half is algorithms over slices and integers: sorting, the hash function and the table's probing, UTF-8, the Unicode tables, float conversion, and thin bindings to libc. §4 lists it as Wave A, which can start now. Wave B needs 0.17, Wave C needs 0.18, and Wave D needs 0.19.

## 1. Current state, measured

**std's shape.**
- std is one module, `std`: 5,538 lines in compiler/std/*.vl, joined by embed.sh into the text built into the compiler.
- A program gets std when it names it or a prelude name. Only the *sections* it reaches are lexed (front/modules/stdsections.vl, from 0.15). The compiler picks Gpa's implementation at the end of the text (gpa.vl, or alloc_check.vl with `--check-alloc`). That is the only per-build choice of std code.
- A hello world compiles in 32 ms at -O0.
- There is no `#[cfg]`. There are no std submodules: `std::collections::HashMap` does not resolve.

**Collections.**
- `Vec<T, A>` and `Buf<A>` are 24-byte handles.
- `HashMap<K, V, A>` is open addressing with linear probing:
  - three allocations (keys, values, one state byte per slot);
  - load factor 3/4;
  - `Hash::hash(self: *Self) -> u64`: FNV-1a byte by byte for `[u8]`, splitmix64's finalizer for integers, combined by `hash_mix`;
  - iteration through `slots()`, `key_at(i)` and `value_at(i)`, in slot order. The order is deterministic, and tests print in it.
- `sort` is an introsort and is not stable. `sort_stable_in` is a merge sort with a buffer from an allocator. Comparators return `i64`.
- There is no `VecDeque`, `HashSet`, `BTreeMap`, `BinaryHeap`, small vector or bit set. The guide's advice for a set is `HashMap<K, bool>`.

**Text.**
- Text is `[u8]`, and `'a'` is a `u8`. There is no `char`, `str` or `String`, and no UTF-8 validation, decoding, graphemes or width.
- `Scanner`, `split_in`, `split_whitespace_in`, `trim` and `parse_int` work on bytes.
- `Fmt` (0.15) formats integers itself. Floats go through C:
  - `snprintf("%.*e")` at 15, 16 and then 17 digits, each tried with `strtod` until one reads back;
  - the digits are then re-laid out by hand;
  - `{:.N}` is `snprintf("%.*f")`.

**I/O and the system.**
- std declares `read`, `write`, `exit`, `malloc`, `realloc` and `free`, and it does I/O only on fds 0, 1 and 2: `read_line`, `read_stdin_in`, print.
- There are no files, directories, environment, processes, clocks or random numbers. `main(argc, argv, gpa)` gives the raw arguments. Programs that need more import C headers.
- `IoError` is `enum { Read, Write }`.

**Language gaps 0.20 meets.**
- There is no `char`, `str`, `u128`, or const generic parameter (moved out of 0.6 and not done since).
- `Ord::cmp` returns `i64`, not `Ordering`.
- `Hash` returns a `u64`, so a seeded or streaming hasher cannot be plugged in.

**Measured against Rust 1.98** (fastest of 3 runs, whole program, data made in-process with xorshift; the programs are in this session's scratchpad and become bench/std pairs in P0):

| operation | vole -O2 | Rust -O | ratio |
|---|---|---|---|
| format 1M random f64 with `{}` into a buffer | 0.50 s | 0.04 s | **12.5×** |
| sort 5M random u64, unstable (`sort` against `sort_unstable`) | ≈0.27 s | 0.068 s | **≈4×** |
| sort 5M random u64, stable (`sort_stable_in` against `sort`) | ≈0.34 s | 0.100 s | **≈3.4×** |
| HashMap<u64,u64>: 2M inserts, 2M lookups (Rust: default SipHash-1-3) | 0.09 s | 0.07 s | 1.3× |
| word count, 4M words (`[u8]` keys; Rust: `&[u8]` keys, SipHash) | 0.29 s | 0.36 s | 0.8× |

The table wins on strings only because FNV is cheaper than SipHash. With the same hash function, hashbrown's probing would win on both rows (§3 sets the target against equal hash functions). Float formatting and sorting are the large gaps.

## 2. The design (decided)

### 2.1 Principles

1. **Rust's names and shapes wherever they do not allocate implicitly.** The familiar-names research measured the gain: renaming a known API costs models most of their accuracy, and 56% of the 0.16 name/API errors went away with six Rust forms. Its warning applies too: a familiar name with a different meaning is worse than a new name. So the rule is:
   - **R1.** A Rust std item whose semantics vole can keep exactly has Rust's path, name, argument order and result shape: `HashMap::insert -> Option<V>`, `s.split_whitespace()` returning an iterator, `binary_search -> Result<i64, i64>`, `Ordering`, `BufReader::new(f)`, `File::open(p)?`.
   - **R2.** A Rust item that allocates from the global allocator takes an allocator in vole. Its name gets the `_in` suffix and the allocator comes last, as 0.16 already does: `String::new_in(gpa)`, `s.to_uppercase_in(gpa)`, `fs::read_to_string_in(p, gpa)`, `it.collect_in(gpa)`. The Rust spelling exists and is the `alloc.explicit` error, whose `try:` is the `_in` form (0.16's mechanism, `#[ambient]` text).
   - **R3.** Where Rust allocates only as an implementation detail, vole does not allocate and keeps Rust's name:
     - `BufReader::new(f)` has an inline 8 KB buffer;
     - `stdin().lines()` and `BufRead::lines()` yield views of a reused buffer, a lending iterator under 0.17's view rules;
     - `Command::new(p).arg(..)` keeps up to 32 arguments inline;
     - `env::args()` yields views of `argv`.

     The item's documentation states the difference. 0.17's checker reports the only case where it shows, a line kept past the next one, with `try: line.to_string_in(gpa)`.
   - **R4.** A false friend is fixed, not documented. Today's `sort(s)` is unstable, but Rust's `sort` is stable. Today's `Vec::get(i) -> T` panics, but Rust's returns an `Option`. Both change to Rust's meaning in 0.20, and `fix --only std020` rewrites old uses to keep their behaviour (§5).
2. **Every container is allocator-aware (0.16) and a value (0.17).** A container stores its allocator and frees through it in `Drop`. Iterators and lookups return views (`&T`, `[T]`, `str`) under 0.17's second-class rules, so nothing in std hands out a pointer the checker cannot see.
3. **Deterministic by default.** The same program and input give the same output on every target, at every opt level, and with or without SIMD:
   - hash iteration order (§2.4.2);
   - float digits;
   - grapheme boundaries.

   Nondeterminism (a random hash seed, OS entropy, the clock) is opt-in. It carries the `io` effect.
4. **Pure where possible.** Text, number and Unicode routines read only immutable statics, which are not `global`. They are `#[pure]` and `#[no_alloc]`, so `query effects` shows formatting a float as `none`.
5. **Performance is a release criterion.** Every routine of §3 has a bench/std pair (vole, Rust's std, C) with a target, and the 0.20 gate runs them.
6. **No UB.** All indexing is checked or proven, and `unsafe` stays inside std's raw-storage modules. A `str` is valid UTF-8 by construction, and a `char` is a scalar value by construction, so the unchecked constructors are `unsafe fn`.

### 2.2 std becomes a module tree; the prelude grows

- **Paths.** std gets Rust's module paths: `std::collections`, `std::str`, `std::string`, `std::char`, `std::fmt`, `std::io`, `std::fs`, `std::path`, `std::env`, `std::process`, `std::time`, `std::hash`, `std::cmp`, `std::num`, `std::slice`, `std::iter`, `std::mem`, `std::alloc`, `std::os::unix`. Two are vole's own: `std::random` and `std::unicode` (which is public for the terminal's needs).
- **Old names.** Every 0.17 name stays at `std::NAME` through a `pub use` (`// api:` keeps it from `fix --only reexports`). `use std::collections::HashMap;` and `use std::HashMap;` name the same item, and neither is needed for prelude names.
- **Loading.** Each file is one section or more, loaded lazily as today. P0 makes sure a program that reaches only `HashMap` does not lex the Unicode or float tables.
- **Per-target code** without `#[cfg]`. The compiler appends `sys/macos.vl` or `sys/linux.vl`, as it appends gpa.vl today. Both files define the same public items, and a test checks this. `std::TARGET_OS` is an injected constant, like `CHECK_ALLOC`, for code that branches on it (constant-folded).
- **The prelude gains** `String`, `str`, `char`, `Ordering`, `Reverse`, `HashSet`, `BTreeMap`, `BTreeSet`, `VecDeque`, `BinaryHeap`, `ToString`, `FromStr`, `Read`, `Write` and `BufRead`. That is Rust's prelude plus the collections, which vole's prelude already leans toward: missing imports were the largest single fixable class in the research. As before, the prelude comes last, so a program's own `String` hides it.

### 2.3 Language additions 0.20 needs

| | addition | why | needs |
|---|---|---|---|
| L1 | **const generic parameters** `const N: i64` on types, impls and functions, monomorphized as type parameters are; `[T; N]`; arithmetic on N only in array lengths | `SmallVec<T, N>`, `ArrayVec<T, N>`, impls for arrays of any length (Display, Eq, Hash), `[u8; N]` buffers in generic code | nothing (task A8) |
| L2 | **`char`**: a built-in 4-byte type holding a Unicode scalar value (0 to 0x10FFFF, no surrogates); `c as u32`, `c as u8` (truncating, as Rust); `char::from_u32(u) -> Option<char>`; `unsafe fn from_u32_unchecked`. **Literals** `'x'` are typed by context, as integer literals are: `char` or `u8`, and a non-ASCII literal only `char`; with no context, ASCII is `u8` (today's meaning) and non-ASCII is `char`. `b'x'` is accepted as a `u8` literal (Rust's spelling). | text APIs, graphemes and width are about scalar values | nothing (task A9) |
| L3 | **`str`**: a built-in view type, `[u8]` with the invariant that its bytes are UTF-8; the same representation (ptr, len); read-only like 0.17's `[T]`; `&str` in a type is `str`, as `&[T]` is `[T]`. String literals are `str` when they are valid UTF-8 (every literal without a `\x80`–`\xff` escape), and `str` coerces to `[u8]` implicitly and for free. `[u8]` becomes `str` only through `str::from_utf8(b)?` or `unsafe str::from_utf8_unchecked`. `s[a..b]` is a `str`, checked at char boundaries (Rust panics there; so do we). `s[i]` reads byte i as a `u8`: Rust rejects `s[i]`, so this is not a false friend, and it keeps today's literal-indexing code working. **Deref coercions**: `&String` → `str`, `&Vec<T>` → `[T]`, `&Buf` → `[u8]`, `&mut Vec<T>` → `&mut [T]`, in argument and `let`-with-type positions, as Rust's. | `String`'s view; the Rust form `fn f(s: &str)` and `f(&s)` | 0.17's `&`, views (task B5) |

`u128` is not added. `std::num::wide_mul(a, b) -> (u64, u64)` covers the 128-bit products that hashing, float conversion and random ranges need (§2.6.4). In Wave A it is scalar code, and in 0.19 it is a single UMULH plus MUL.

### 2.4 Collections

#### 2.4.1 Vec and slices

- **Shape.** `Vec<T, A>` keeps its layout. With 0.17 it is owned (Drop frees through `A`), and its methods take `&self` or `&mut self`.
- **The Rust API that does not exist yet:**
  - `get(i) -> Option<&T>` and `get_mut(i) -> Option<&mut T>` (0.17.1 projections). Today's checked `get(i) -> T` is R4's false friend, and `fix` rewrites it to `v[i]`.
  - `first`/`last` returning `Option<&T>`.
  - `iter() -> Iter<T>` with `&T` items, and `iter_mut()`.
  - `retain`, `retain_mut`, `dedup`, `dedup_by_key`, `drain(range)`, `extend` (from an iterator), `split_off`, `append`, `swap_remove`, `insert`, `resize`, `resize_with`, `extend_from_within`, `into_iter()`, `contains`, `windows`, `chunks`, `chunks_exact`, `split_at`, `split_first`, `concat_in`, `join_in`, `iter().rev()`.
- **Sorting a Vec** uses the Vec's own allocator for scratch space: `v.sort()` is stable and as fast as Rust's (§2.4.6), and its effect is `alloc(A)`.
- **Slices** (`[T]` read-only, `&mut [T]` exclusive, from 0.17) get Rust's methods: `len()`, `is_empty`, `iter`, `iter_mut`, `first`, `last`, `get`, `split_at`, `windows`, `chunks`, `contains`, `starts_with`, `ends_with`, `binary_search(_by, _by_key)`, `partition_point`, `sort`, `sort_by`, `sort_by_key`, `sort_unstable(_by, _by_key)`, `select_nth_unstable`, `reverse`, `rotate_left`, `rotate_right`, `fill`, `copy_from_slice`, `swap`, `to_vec_in`. `s.sort()` on a slice has no allocator: it is stable, uses a 4 KB stack buffer, and falls back to in-place merging beyond that (§2.4.6).
- **`DoubleEndedIterator`** (`next_back`, `rev`) and `ExactSizeIterator` join `Iterator`. `chars().rev()` and `iter().rev()` are among the forms agents write most.

#### 2.4.2 HashMap and HashSet: a Swiss table

**Hashing (std::hash), in Rust's shape:**

```
pub trait Hasher {
    fn write(self: &mut Self, bytes: [u8]);
    fn write_u8(self: &mut Self, x: u8) { .. }  // .. write_u64, write_i64, write_usize-as-i64: defaults through write_u64
    fn write_u64(self: &mut Self, x: u64);
    fn finish(self: &Self) -> u64;
}
pub trait Hash { fn hash<H: Hasher>(self: &Self, state: &mut H); }   // derive(Hash): field by field
pub trait BuildHasher { type Hasher: Hasher; fn build_hasher(self: &Self) -> Self::Hasher;
                        fn hash_one<T: Hash>(self: &Self, x: &T) -> u64 { .. } }
pub struct FixedState { seed: u64 }     // the default: a fixed seed, deterministic
pub struct RandomState { seed: u64 }    // RandomState::new(): a per-process random seed (io)
pub struct SipHashState { k0: u64, k1: u64 }  // SipHash-1-3 with random keys: Rust's default, for hostile input
pub struct FoldHasher { .. }            // what FixedState and RandomState build
```

- **The default hasher is foldhash's "fast" algorithm** (Orson Peters, 2024, hashbrown's default since 0.15), with a fixed seed. Its core is the folded multiply `fold_mul(a, b) = hi(a×b) ^ lo(a×b)` through `wide_mul`.
  - An integer key costs one multiply.
  - Bytes are consumed 16 at a time, with separate paths for 0–16 and 17–128 bytes.
  - `[u8]`, `str` and `String` hash their bytes with one `write`, plus a length suffix, as Rust does (so `("ab","c")` and `("a","bc")` differ).
- **Why a fixed seed, which Rust does not use:**
  - determinism (§2.1.3): tests, `same-output`, and 0.18's `-O0` against `-O2` comparison all print maps;
  - effects: a random seed makes `HashMap::new_in` `io`;
  - speed.
- **Hostile input** gets `HashMap::with_hasher_in(RandomState::new(), gpa)`. Fully adversarial input gets `SipHashState`. The guide says this in its first paragraph on maps. Seeded foldhash is not cryptographically flood-proof. SipHash is the documented answer when keys come from an attacker.
- **`hash_of(x)`** stays, hashing with `FixedState`.

**The table, `RawTable<T, A>`** (std::collections::raw, private), is hashbrown's design:

- **One allocation:** the buckets (`T`, the map's `(K, V)`) followed by the control bytes (`cap + GROUP` of them, the tail mirroring the head). `cap` is a power of two.
- **Control byte:** `EMPTY = 0xFF`, `DELETED = 0x80`, or `FULL = h2` (the hash's top 7 bits, 0x00–0x7F).
- **h1** (the hash's low bits masked) picks the starting group.
- **Probing is triangular over groups** (`pos += stride; stride += GROUP`), which visits every group of a power-of-two table. Each group is matched at once:
  - `match_tag(h2)`: the candidates, compared by `Eq` only on a tag hit;
  - `match_empty`: the end of the search;
  - `match_empty_or_deleted`: the insertion slot.
- **Load factor 7/8.** Tables under 8 buckets hold `cap - 1`.
- **Erase** writes `EMPTY` when no probe sequence can have passed the slot (hashbrown's leading-and-trailing-empties test), else `DELETED`.
- **Growth.** When `growth_left` reaches 0, the table rehashes in place if at least half the slots are tombstones, else it doubles.
- **No hashing inside the table.** The caller passes the hash and closures: `find(hash, eq)`, `insert(hash, x, hasher)`. So HashMap and HashSet share one table, and the table's code is not instantiated per key type twice.
- **The SIMD seam is `Group`**:

  ```
  const GROUP: i64 = 8;                       // every target, every implementation
  fn group_load(ctrl: *u8, pos: i64) -> Group  // Group = u64 in the scalar version
  fn match_tag(g: Group, h2: u8) -> BitMask    // BitMask = u64, one bit per byte (0x80 lanes)
  fn match_empty(g: Group) -> BitMask
  fn match_empty_or_deleted(g: Group) -> BitMask
  fn match_full(g: Group) -> BitMask
  fn convert_special_to_empty_and_full_to_deleted(g: Group) -> Group   // in-place rehash
  fn lowest(m: BitMask) -> i64;  fn remove_lowest(m: BitMask) -> BitMask
  ```

  - The scalar version is SWAR on a `u64`, hashbrown's `generic.rs`. Its `match_tag` can return false positives, which the `Eq` check absorbs.
  - 0.19's NEON version uses `uint8x8_t`, also 8 bytes wide, as hashbrown does on aarch64.
  - **The group width is 8 everywhere.** Even SSE2, whose natural width is 16, uses the low 8 lanes. So a table's layout, and therefore its iteration order, is the same on every target and with SIMD on or off. Task D1 tests this bytewise.
- **Iteration** is in bucket order, found by `match_full` over the control bytes.

**The public API** (B2) is Rust's:

- **Construction:** `new_in`, `with_capacity_in`, `with_hasher_in`.
- **Size:** `len`, `is_empty`, `capacity`, `reserve`, `shrink_to_fit`, `clear`.
- **Lookup:** `insert -> Option<V>`, `get(&Q) -> Option<&V>`, `get_mut`, `get_key_value`, `contains_key`, `remove -> Option<V>`, `remove_entry`.
- **Entries:** `entry(k) -> Entry` (`or_insert`, `or_insert_with`, `or_default`, `and_modify`, `key`).
- **Iteration:** `iter`, `iter_mut`, `keys`, `values`, `values_mut`, `into_iter`, `drain`, `retain`, `extend`.
- **Borrowed lookups** go through `Borrow<Q>`. `HashMap<String, V>` is looked up with a `str`. `Borrow` is implemented for `String → str`, `Vec<T> → [T]`, `Buf → [u8]` and `T → T`, and std guarantees `Hash` and `Eq` agree across each pair.

`HashSet<T, S, A>` wraps `RawTable<T>`, with Rust's set operations (`union`, `intersection`, `difference`, `symmetric_difference`, `is_subset`, as iterators).

**What happens to 0.15 to 0.17 forms:**
- `get_or_insert(k, d)` stays one release as a deprecated alias of `*entry(k).or_insert(d)`, and `fix` rewrites it.
- `slots`, `key_at` and `value_at` are deprecated in favour of `iter()`.
- `HashMap<[u8], V>` (view keys) stays legal under 0.17's rules for containers of views.

#### 2.4.3 BTreeMap and BTreeSet

- **The layout is Rust's**, which is proven and needs no stack to iterate:
  - B = 6, so a node holds up to 11 keys and 11 values inline;
  - internal nodes add 12 child pointers;
  - every node has a `parent` pointer and a `parent_idx`;
  - leaves and internal nodes are allocated through `A` at their own sizes.
- **Search** within a node is linear. With 11 keys this beats binary search, and 0.19 may compare integer keys with SIMD.
- **Insert** splits at the median when full and propagates up. **Remove** steals from a sibling, or merges, and shrinks the root.
- **Drop** frees post-order iteratively, through the `parent` links, without recursion.
- **API:** Rust's, with `range(a..b)` and `range_mut` through 0.17 views, plus `first_key_value`, `last_key_value`, `pop_first`, `pop_last`, `entry` and `split_off`.

#### 2.4.4 VecDeque, BinaryHeap, SmallVec and ArrayVec, BitSet

- **`VecDeque<T, A>`** is Rust's current design: `head + len` over any capacity, with a conditional subtraction instead of a modulo. It provides `as_slices`, `make_contiguous`, and O(1) `From<Vec>`.
- **`BinaryHeap<T: Ord, A>`** is a max-heap, as agents expect, and `Reverse<T>` (in the prelude) makes a min-heap. `pop` uses Rust's sift-down-to-bottom-then-up, and `into_sorted_vec` and `peek_mut` are included.
- **`SmallVec<T, const N: i64, A>`** keeps N elements inline, then moves to the allocator. It is smallvec 2.0's spelling.
- **`ArrayVec<T, const N>`** never allocates. `push` is checked, `try_push` returns an `Err`, and it is the container for `#[no_alloc]` code. It shares the inline half of SmallVec's code.
- **`BitSet<A>`** is growable `u64` words: `insert`, `remove`, `contains`, `len` (`count_ones`), `union_with`, `intersect_with`, `difference_with`, and `iter` (a `trailing_zeros` loop). `FixedBitSet<const N>` is its inline form. Rust's std has no bitset, so the API follows the `fixedbitset` and `bit-set` crates' names.

#### 2.4.5 Ordering

- `enum Ordering { Less, Equal, Greater }` with `reverse`, `then`, `then_with`, `is_lt` and the rest.
- `Ord::cmp(&self, &Self) -> Ordering`, with `PartialOrd::partial_cmp -> Option<Ordering>` for floats, plus `f64::total_cmp`.
- `min`, `max` and `clamp` on `Ord`. `cmp_of` returns `Ordering`.
- Comparators (`sort_by`, `max_by`, `binary_search_by`) return `Ordering`.

This is a breaking change, and A0 does it now, with its `fix` rule (§5). It also removes the overflow bug of `|a, b| a.x - b.x` comparators on extreme values.

#### 2.4.6 Sorting and searching

- **`sort_unstable`** follows ipnsort's structure (Rust 1.81's unstable sort):
  - full-run detection, so sorted and reversed input costs O(n);
  - insertion sort below 20;
  - a branchless cyclic Lomuto partition;
  - median-of-3 pivots, with a recursive pseudo-median above 64;
  - a heapsort fallback at depth 2·log2(n);
  - equal-element partitioning when the pivot equals the previous one, so few-unique input costs O(n log k).
- **The stable sort** comes in two phases:
  1. A powersort merge policy over natural runs (as Python 3.11 and driftsort use). Short runs are extended to 20 with insertion sort, merges are branchless and bidirectional, and the scratch space is n/2.
  2. Only if the bench misses its target (§3), driftsort's lazy logical runs, sorted with quicksort.

  Where the scratch comes from:
  - `v.sort()` on a Vec, from `v.allocator()`;
  - `sort_in(s, a)`, from `a`;
  - `s.sort()` on a slice, from a 4 KB stack buffer. When n/2 elements do not fit, merges are done in place by rotation (SymMerge, O(n log² n)). The guide says so, and points to `v.sort()` or `sort_unstable()` for speed.
- **Search:** branchless `binary_search` (Rust's form returns `Result<i64, i64>`), `partition_point`, and `select_nth_unstable` (introselect, median of medians as the fallback).

### 2.5 Text

#### 2.5.1 The four types

| type | is | owns | made by |
|---|---|---|---|
| `[u8]` | bytes, any content | no (a view) | slicing, literals with `\x80`+ escapes, I/O buffers |
| `str` | UTF-8 bytes | no (a view) | literals, `str::from_utf8(b)?`, `&string`, `s[a..b]` |
| `String<A = Gpa>` | UTF-8 bytes, growable | yes (a `Vec<u8, A>` inside) | `String::new_in(gpa)`, `format_in`, `to_string_in`, `String::from_utf8(v)?` |
| `Buf<A = Gpa>` | bytes, growable, with text helpers | yes | as today; it is Rust's `Vec<u8>` used as `io::Write` |

- **`Buf` stays.** It is the byte buffer agents already use, and it implements `io::Write`.
- **`String` is new, not an alias of `Buf`.** The research found `String` as an alias would be a false friend for bytes, and the roadmap asks for UTF-8 text. `String` is what the text APIs return. The two convert explicitly: `String::from_utf8(buf)?` validates, and `s.into_bytes()` gives a `Vec<u8>`.
- **`format_in` returns a `String`.** f-strings themselves do not allocate (0.15), so `print(f"..")` is unchanged.

#### 2.5.2 `str` and `String` methods (B5)

**Without an allocator, under Rust's names:**
- `len`, `is_empty`, `as_bytes`, `chars`, `char_indices`, `bytes`, `lines`, `split(pat)`, `splitn`, `rsplit`, `split_terminator`, `split_once`, `rsplit_once`, `split_whitespace`, `split_ascii_whitespace`, `matches`, `match_indices`;
- `trim`, `trim_start`, `trim_end`, `trim_matches`, `strip_prefix`, `strip_suffix`;
- `starts_with`, `ends_with`, `contains`, `find`, `rfind`, `is_char_boundary`, `eq_ignore_ascii_case`, `make_ascii_uppercase` (on `&mut str`);
- `parse::<T: FromStr>()`;
- from unicode-segmentation, `graphemes(true)` and `grapheme_indices(true)` (the crate's spelling, flag included);
- from unicode-width, `width()` and `width_cjk()`.

The iterators are views (`views(self)` in 0.17's summaries) and are double-ended where Rust's are.

- **`Pattern`** is implemented for `char`, `str`, `[char; N]` and `FnMut(char) -> bool`. Searching a `str` pattern uses a two-way search above 32 bytes and a byte-at-first-position loop below. 0.19 adds memchr.
- **Allocating, under R2:** `to_uppercase_in`, `to_lowercase_in`, `replace_in`, `replacen_in`, `repeat_in`, `to_string_in`, `to_owned_in` and `String::from_in`. The Rust forms are `alloc.explicit` errors whose `try:` is the `_in` call.
- **`String`:** `new_in`, `with_capacity_in`, `push(char)`, `push_str(str)`, `+=` with a `str`, `pop -> Option<char>`, `insert`, `insert_str`, `remove`, `truncate`, `clear`, `drain(range)`, `retain`, `as_str`, `as_bytes`, `capacity`, `reserve`, `into_bytes`, and `from_utf8_lossy_in`. It implements Display, Debug, Eq, Ord, Hash, `Borrow<str>` and `fmt::Write`.
- **`char`:** `is_alphabetic`, `is_numeric`, `is_alphanumeric`, `is_whitespace`, `is_lowercase`, `is_uppercase`, `is_control`, the `is_ascii_*` family, `to_ascii_uppercase`/`to_ascii_lowercase`, `to_lowercase()`/`to_uppercase()` (iterators of up to 3 chars, as Rust's), `to_digit(radix)`, `char::from_digit`, `len_utf8`, `encode_utf8(&mut [u8; 4]) -> str`, `width() -> Option<i64>` (unicode-width's: `None` for controls), `width_cjk`.
- **`FromStr`** is implemented for every integer type, `f32`, `f64`, `bool` and `char`, and `ToString` is a blanket impl over Display (`to_string_in`).

#### 2.5.3 UTF-8 (A4, then D2)

- **Validation** (`str::from_utf8`) reports Rust's `Utf8Error { valid_up_to, error_len: Option<i64> }`.
  - Scalar: an ASCII fast path tests 16 bytes per step as two `u64`s against `0x8080…`, aligned. Non-ASCII bytes go through Rust's `core::str::validations` decision (a width table, then range checks on the second byte).
  - 0.19: Keiser and Lemire's lookup algorithm ("Validating UTF-8 in less than one instruction per byte", simdutf), 16 bytes per NEON step, with the scalar version as the tail and as the oracle.
- **Decoding:** `chars()` decodes with Rust's `next_code_point` (branchy, right for mostly-ASCII text). Bulk decoding, for the terminal, is `decode_into(bytes, out: &mut [u32]) -> (consumed, produced)`, which widens ASCII by SWAR, eight bytes at a time.
- **Streaming:** `Utf8Decoder` keeps up to 3 pending bytes across buffer boundaries. Invalid input produces U+FFFD per *maximal subpart*, which is Unicode's recommended practice and what WHATWG, Rust's `from_utf8_lossy` and terminals do.
- **Small helpers:** `encode_utf8`, `count_chars` (counts non-continuation bytes, with SWAR), `ascii_prefix_len`, `ascii_printable_prefix_len` (bytes 0x20–0x7E, the terminal parser's fast path), and `floor_char_boundary`/`ceil_char_boundary`.

#### 2.5.4 Unicode properties, graphemes, display width (A5)

- **Unicode version.** The newest Unicode release when A5 starts (17.0 or later). Its version and the SHA-256 of each UCD file it reads are pinned in tools/unicode/ucd.lock. `std::unicode::UNICODE_VERSION` names it.
- **The generator is tools/unicode/gen.vl, a vole program.** It dogfoods the language and reads files through `import "stdio.h"` until A7's layer exists.
  - **Input:** UnicodeData.txt, DerivedCoreProperties.txt, PropList.txt, EastAsianWidth.txt, emoji-data.txt, GraphemeBreakProperty.txt, SpecialCasing.txt and CaseFolding.txt, downloaded into a cache outside the tree by tools/unicode/fetch.sh and checked against the lock.
  - **Output:** compiler/std/unicode/tables.vl, checked in and marked generated.
  - **Check:** `gen.vl --check` regenerates the tables and compares them, and the gate runs it when the cache is present.
  - **Tests:** the test files (GraphemeBreakTest.txt, emoji-test.txt) are copied into tests/std/unicode/, where tests read them.
- **One properties lookup per code point.** `props(cp: u32) -> u16` packs:
  - the Grapheme_Cluster_Break value (4 bits);
  - the width class (2 bits: 0, 1, 2, or ambiguous);
  - Extended_Pictographic (1);
  - Indic_Conjunct_Break (2: None, Linker, Consonant, Extend);
  - Emoji_Presentation (1);
  - White_Space (1);
  - spare bits.
- **The trie** has three stages: `cp >> 11` gives a stage-2 block, `(cp >> 5) & 63` a stage-3 block, and the stage-3 blocks are deduplicated runs of 32 `u16` values. Code points below 0x100 bypass it through a 256-entry table. The generator chooses the shift sizes that minimize the bytes, and the target is at most 24 KB for `props`.
- **Other tables.** Alphabetic, Numeric, Lowercase and Uppercase are bitsets in a two-level skip list, as Rust's core::unicode does. Case mappings are sorted `(cp, mapping)` arrays searched by binary search, plus SpecialCasing's one-to-many mappings.
- **Graphemes** are UAX #29 extended grapheme clusters: rules GB1 to GB999, including GB9c (Indic conjuncts, from 15.1), GB11 (emoji ZWJ sequences) and GB12/13 (regional-indicator pairs).
  - `GraphemeState` is a few bytes: the previous GCB value, regional-indicator parity, an emoji-sequence state and an InCB state. `push(cp) -> bool` says whether a boundary precedes `cp`, so code points can be fed one at a time, which is what the terminal does.
  - The pair rules are a 16×16 table of break, no-break or "consult the state".
  - An ASCII pair breaks unless it is CR LF, without a lookup.
  - `GraphemeBreakTest.txt` must pass in full. An unoptimized implementation written rule by rule from the UAX text is kept in tests as the oracle.
- **Display width.**
  - **Per code point** (`char::width`), unicode-width's semantics: 2 for East_Asian_Width W or F; 0 for Mn, Me, Cf (except U+00AD), ZWSP, ZWJ, the Hangul medial and final jamo (U+1160–U+11FF) and the variation selectors; `None` for C0 and C1 controls; 1 for the rest. Ambiguous is 1, and 2 under `width_cjk`.
  - **Per grapheme** (`str::width`, `grapheme_width`):
    - 2 if the cluster has an Emoji_Presentation base, or any Extended_Pictographic base followed by VS16, or is a regional-indicator pair;
    - 1 for a text-presentation emoji with VS15;
    - otherwise the width of its first code point, or 0 if every code point is zero-width.
  - **Both, because terminals differ.** Alacritty, the 0.23 comparison, is per code point. Kitty, WezTerm and Ghostty in mode 2027 are per grapheme. The terminal example picks with a setting.
- **Tests for width:** every fully-qualified sequence in emoji-test.txt is 2; EastAsianWidth.txt's W and F ranges are 2; plus a hand list of the unicode-width crate's documented cases.

#### 2.5.5 Numbers (A6)

- **`wide_mul(a, b) -> (hi, lo)`** in std::num. The scalar version uses four 32×32 products. In 0.19 it is `std::arch::wide_mul`, a single instruction pair.
- **Integer formatting** follows itoa and Rust: a two-digit lookup table, writing from the end of a `[u8; 20]`. It replaces `Fmt::int`'s loop, with byte-identical output. **Integer parsing** is `parse_i64_radix` and `parse_u64_radix`: checked accumulation with an overflow check per digit, a fast path of 8 digits at a time by SWAR for decimal, and Rust's `FromStr` grammar (an optional `+` or `-`, no whitespace, no `_`). `ParseIntError` keeps its 0.15 variants and gains `kind()` with Rust's `IntErrorKind` names.
- **Float formatting is Schubfach** (Giulietti, 2020; Java 19's `Double.toString`), which finds the shortest correctly rounded digits:
  - one 128×64-bit multiply per bound, against a 617-entry table of 128-bit powers of ten (about 10 KB);
  - the table is generated by tools/numtables/gen.vl, using big integers, and checked in;
  - `f32` has its own 64-bit table.
- **The output formats match Rust's text exactly:**
  - Display: no exponent, `1e16` written out in full;
  - Debug: `1.0`, `1e16`, `1e-7`;
  - `{:e}` and `{:E}`: new, LowerExp and UpperExp.
- **`{:.N}` stays on `snprintf("%.*f")`** in phase 1. libc's fixed-precision output is correctly rounded on macOS and glibc. It moves to a Ryu-printf port only if the bench row `fmt_f64_prec` misses its target.
- **Float parsing is Rust's dec2flt pipeline**, which is also fast_float's:
  1. Parse into a mantissa (`u64`, up to 19 digits), an exponent and a many-digits flag.
  2. Clinger's fast path when the mantissa is at most 2^53 and |exp| is at most 22.
  3. Eisel and Lemire, with a 128-bit table of powers of five for q from -342 to 308 (651 entries, about 10 KB, same generator).
  4. The simple-decimal fallback (Nigel Tao's, as in Rust's `parse_long_mantissa`) for the rare ambiguous cases.

  The grammar is Rust's `f64::from_str`: `inf`, `infinity` and `nan` in any case, an optional sign, `1.`, `.5`, `1e5`; no hex, no `_`, no whitespace. `ParseFloatError` is Rust's.
- **Tests:**
  - f32 exhaustively round-trips (format, parse, same bits for all 2^32), in `gate --release` only;
  - 10^8 random f64 round-trip, and each result is checked to be the shortest by verifying that one digit fewer does not read back;
  - Display and Debug are compared byte for byte with Rust's output on a corpus of 10^6 values made by a Rust oracle program (tests/std/oracle/fmt_f64.rs, run by the test script when rustc exists; the expected file is checked in, compressed);
  - parsing is compared with `strtod` on 10^7 generated strings, plus the known hard cases (halfway points, 768-digit inputs, subnormals).

### 2.6 I/O and the system

#### 2.6.1 Layers

| layer | module | what | Wave |
|---|---|---|---|
| sys | `std::sys` (private), sys/unix.vl plus sys/{macos,linux}.vl | `extern "C"` libc bindings with declared effects; `#[repr(C)]` structs per target; errno; results as `Result<T, i32>` | A7 |
| os | `std::os::unix` | `RawFd`, `pty`, `poll`, `isatty`, the terminal's ioctls | A7 (sys), B6 (types) |
| io | `std::io`, `fs`, `path`, `env`, `process`, `time`, `random` | the safe API: owned handles with Drop, `io::Error`, the traits | B6 |

- **libc on both targets, no raw syscalls.** macOS has no stable syscall ABI, and Linux's libc costs nothing measurable at this level.
- **Bindings are written by hand, per target, not imported** with `import "sys/stat.h"`. Importing runs the C preprocessor on every compile, and needs a C compiler.
- **A test checks the hand-written layouts against the headers** (`stat`, `timespec`, `dirent`, `winsize`, `termios`, `pollfd`), as the header-layout tests already do for user programs.

#### 2.6.2 Errors

- **`io::Error`** is Rust's shape without its `Box`: `struct Error { kind: ErrorKind, code: i32, msg: str }`.
  - `code` is the OS errno, or 0.
  - `msg` is a static `str` for std's own errors (∅ origin under 0.17), or empty.
  - Methods: `kind()`, `raw_os_error() -> Option<i32>`, `Error::new(kind, msg: str)` (static messages only), `Error::other(msg)`, Display (`strerror_r` into the formatter, no allocation) and Debug.
- **`ErrorKind`** has Rust's variants that vole can produce: NotFound, PermissionDenied, AlreadyExists, WouldBlock, InvalidInput, InvalidData, TimedOut, WriteZero, Interrupted, UnexpectedEof, BrokenPipe, NotADirectory, IsADirectory, DirectoryNotEmpty, Unsupported, OutOfMemory and Other.
- **The old name.** `io::Result<T>` is `Result<T, io::Error>`. `IoError` remains one release as a type alias of `io::Error`, and `fix` rewrites patterns on `IoError::Read` and `IoError::Write`.
- **`?` converts** through `From`, as in 0.15.

#### 2.6.3 The API (B6)

- **Traits**, Rust's:
  - `Read`: `read`, `read_exact`, `read_to_end` on a `&mut Vec<u8, A>`, `read_to_string` on a `&mut String<A>`; the buffers carry their allocators, so no `_in` is needed;
  - `Write`: `write`, `write_all`, `flush`, `write_fmt(x: impl Display)`;
  - `BufRead`: `fill_buf`, `consume`, `read_line(&mut String) -> io::Result<i64>`, which appends and keeps the `\n` (Rust's meaning, `Ok(0)` at the end), `read_until`, and `lines()` and `split(b)`, which are lending view iterators (R3).
- **`writeln(w, f"..")`** and `write(w, f"..")` are free functions standing in for Rust's macros.
- **Readers and writers.**
  - `BufReader<R>` and `BufWriter<W>` have an 8 KB inline buffer (R3), so `BufReader::new(f)` does not allocate. A move copies the struct, and 0.17's move elision removes the copy in the usual construct-then-use code. `with_capacity_in(n, inner, a)` puts the buffer on the heap.
  - `LineWriter` too.
- **Standard streams.**
  - `stdin()`, `stdout()` and `stderr()` return handles to process-wide buffers (statics, so `global`).
  - `lock()` exists, and returns the same handle until 0.21's threads.
  - stdout is line-buffered on a terminal and block-buffered otherwise, and it is flushed at exit, before a read from stdin, and on panic. `print` and `println` share its buffer, as today's `Fmt` fd buffer becomes stdout's.
  - The free function `read_line(&buf) -> Result<bool, IoError>` (0.15) keeps its meaning. Its shape differs from Rust's method, so it is not a false friend, and `fix` can move it to `stdin().read_line`.
- **`fs`:**
  - `File::open`, `File::create` and `OpenOptions`; `File` is Read + Write + Seek, and Drop closes it;
  - `metadata`, `set_len`, `sync_all`;
  - `fs::read_in`, `fs::read_to_string_in` and `fs::write` (no allocation);
  - `create_dir(_all)`, `remove_file`, `remove_dir(_all)`, `rename`, `copy`;
  - `read_dir(p) -> ReadDir`, whose `DirEntry` holds the name inline (up to 256 bytes);
  - `canonicalize_in`, `exists`.

  Paths reach C through a NUL-terminated copy in a stack `[u8; 1024]` (macOS) or `[u8; 4096]` (Linux). A longer path is `InvalidInput` and nothing is allocated. A path containing a NUL is also `InvalidInput`.
- **`path`:** `Path` is a view type over bytes (Unix paths are bytes, as Rust's `OsStr` on Unix is). It has `join_in`, `parent`, `file_name`, `extension`, `file_stem`, `components`, `is_absolute`, `display()` and `to_str() -> Option<str>`. `PathBuf<A>` is owned, with `push` and `pop`.
- **`env`:**
  - `args()` yields `str` views of `argv`, with ∅ origin, valid for the whole program; a non-UTF-8 argument panics, as in Rust, and `args_os()` yields `[u8]`;
  - `var_in(name, gpa) -> Result<String, VarError>`, because `environ` can change, so a view would dangle;
  - `var_os`, `vars_in`, `current_dir_in`, `set_current_dir`;
  - `unsafe fn set_var` and `remove_var` (Rust 2024 made them unsafe for the same reason).

  The front end's main wrapper stores `argc`, `argv` and `environ` into std statics when `std::env` is reached.
- **`process`:**
  - `Command::new(prog)` (32 arguments and 16 environment changes inline, R3; `Command::new_in` for more), `arg`, `args`, `env`, `env_remove`, `current_dir`, `stdin`/`stdout`/`stderr(Stdio::piped() | inherit() | null())`;
  - `spawn() -> io::Result<Child>` through `posix_spawnp`, with file actions for the pipes;
  - `output_in(gpa)` and `status()`;
  - `Child` has `wait`, `try_wait`, `kill`, `id` and the pipe ends `ChildStdin`/`ChildStdout`/`ChildStderr` (Read or Write, Drop closes);
  - `exit(code)`.
- **`os::unix`** has what 0.23 needs:
  - `pty::open(size) -> io::Result<Pty>`, with `Pty::resize(rows, cols, px)` (`TIOCSWINSZ`);
  - `pty::spawn(cmd, &pty) -> io::Result<Child>`. It uses `fork`, then in the child only async-signal-safe calls (`setsid`, `ioctl(TIOCSCTTY)`, `dup2`, `execve`), with argv and envp built before the fork;
  - `poll(&mut [PollFd], timeout) -> io::Result<i64>`, `set_nonblocking`, `isatty`, raw-mode termios helpers.
- **`time`:**
  - `Duration` has `secs: u64, nanos: u32`, checked arithmetic, `as_secs_f64` and `from_millis`;
  - `Instant::now()` reads `clock_gettime(CLOCK_MONOTONIC)` (`io`), with `elapsed` and `duration_since`;
  - `SystemTime::now()` and `UNIX_EPOCH`;
  - `std::thread::sleep(d)`, which comes early: 0.21 fills the rest of `thread`.
- **`random`:** Rust's std has none, so the names are rand 0.9's, which models know.
  - `Rng` is xoshiro256++, with 32 bytes of state.
  - `Rng::seed_from_u64(n)` (splitmix64) is pure and deterministic. `Rng::from_entropy()` (`getentropy`) is `io`. `std::random::fill_bytes(&mut [u8])` gives OS randomness.
  - Methods: `next_u64`, `next_u32`, `random::<T>()` for integers, `f64` in [0, 1) and `bool`; `random_range(a..b)` (Lemire's nearly divisionless method, through `wide_mul`); `random_bool(p)`; `fill`.
  - `s.shuffle(&mut rng)` (Fisher–Yates) and `s.choose(&mut rng)` are slice methods.

### 2.7 Effects, contracts, unsafe

- **Effects follow 0.16's table:**
  - container growth is `alloc(A)`;
  - indexing and `unwrap` are `panic`;
  - hashing, UTF-8, Unicode, number conversion and formatting into a `[u8; N]` or a `String` are `none` (immutable static tables are not `global`);
  - the clock, entropy, files, processes, environment and `RandomState::new()` are `io`;
  - `env::args()` and the std streams are `global`.

  `query effects` therefore shows `f.float(v)` as `none` once its C round-trip is gone. Today it is `io global panic unsafe`.
- **Contracts and checks:**
  - under 0.18, every container states its invariants (`invariant` on RawTable's `items + growth_left`, BTree node lengths, `String`'s validity under a debug flag);
  - public preconditions are checked panics with Rust's messages (`index out of bounds: the len is 3 but the index is 5`);
  - `--check-alloc` covers every container through its allocator.
- **Unsafe** stays inside the raw modules: collections/raw_table, btree_node, vec, vec_deque, small_vec, string's unchecked constructors and sys. Each module's header states its safety argument, as std.vl's does today.

### 2.8 What agents see

The Rust an agent writes first, and what happens in 0.20:

| Rust written | 0.20 |
|---|---|
| `use std::collections::HashMap;` | works (also without the `use`: prelude) |
| `let mut m = HashMap::new();` | `alloc.explicit`, `try: HashMap::new_in(gpa)` (0.16's) |
| `*m.entry(w).or_insert(0) += 1;` | works (0.17.1 projections) |
| `for (k, v) in &m` / `m.iter()` | works; order deterministic |
| `let s = String::new();` / `s.to_string()` / `format!(..)` | `alloc.explicit`, `try: String::new_in(gpa)`, `try: s.to_string_in(gpa)`; `format_in(f"..", gpa)` (guide rust) |
| `fn f(s: &str) -> usize` | `&str` is `str`; `usize` gets the existing help (`i64`) |
| `for c in s.chars().rev()` | works |
| `for w in line.split_whitespace()` | works, no allocation |
| `let n: i64 = s.trim().parse().unwrap();` | works |
| `let v: Vec<&str> = s.split(',').collect();` | `alloc.explicit`, `try: .collect_in(gpa)` |
| `v.sort(); v.sort_by(\|a, b\| b.1.cmp(&a.1)); v.sort_unstable_by_key(\|x\| x.0)` | works (Ordering) |
| `let h = BinaryHeap::new(); h.push(Reverse(d));` | `alloc.explicit` then works |
| `let f = File::open(p)?; let r = BufReader::new(f); for line in r.lines() { let line = line?; .. }` | works, no allocation |
| `let text = std::fs::read_to_string(p)?;` | `alloc.explicit`, `try: fs::read_to_string_in(p, gpa)?` |
| `let args: Vec<String> = env::args().collect();` | `alloc.explicit`, `try: let args: Vec<str> = env::args().collect_in(gpa);` |
| `let line_kept = line;` then the next `lines()` item | 0.17 `own.conflict` at the use, `try: line.to_string_in(gpa)` |
| `use rand::Rng; rng.gen_range(0..n)` | `unknown module 'rand'`, help `std::random::Rng`; `gen_range` → nearest name `random_range` (0.17's nearest-names) |

The guide gets three topics, `collections`, `text` and `io`, each in the 0.17 guide style: the most-used list first, then the API index generated from std. guide rust's table loses its "no String, no char, no file reading" rows.

### 2.9 Alternatives considered

- **`String` as an alias of `Buf`, and no `str`.** This is the research's (d) recommendation for 0.17. It was right while text had no UTF-8 operations. Graphemes, width, `chars` and the terminal need validity, and a validated type is where the check lives once. The false friend the research feared (`String::new()`) is handled by R2's error, as `Vec::new()` already is.
- **Rust's random-seeded SipHash default.** It is about 2× slower on integer keys, and it makes iteration order differ between runs, which breaks tests, `same-output` and `-O0`/`-O2` comparison. It also makes map construction `io`. Rejected as the default, and kept as an opt-in.
- **Keeping linear probing, or Robin Hood with backward-shift deletion.** Robin Hood keeps probe lengths low without tombstones, but its insert swaps elements. The Swiss table's tag filtering compares one byte per slot before touching keys, which is what makes `[u8]` and `String` keys fast. It is hashbrown's proven layout and the natural SIMD shape. Chosen.
- **A group width of 16 on SSE2.** Faster on x86, but iteration order would differ between targets. Rejected: 8 everywhere.
- **Float conversion:**
  - Ryu: tables larger than Schubfach's, similar speed;
  - Dragonbox: about 1.3× faster than Schubfach, but about 3× the code and a harder proof; it stays a later option behind the same interface;
  - Grisu with a Dragon4 fallback (Rust's): slower, and two algorithms.

  Schubfach chosen.
- **Raw syscalls on Linux, or `import` of C headers in std.** Raw syscalls would be two code paths. Header imports would run the C preprocessor on every compile. Rejected for hand-written libc bindings with a layout test.
- **`#[cfg(target_os)]`.** It is a language feature, and per-target std files cover 0.20's needs. Deferred to a later release, and to the 1.0 surface work.
- **ICU-scale Unicode** (normalization, collation, bidi, line breaking). Not needed by the terminal, and large. Normalization (NFC/NFD) is the most likely next one, but not in 0.20.
- **Heap-allocated `BufReader` buffers** (Rust's). They would make the commonest Rust form an `alloc.explicit` error. The inline buffer costs a memcpy on an unelided move. Inline chosen.
- **`Vec<T>::get` kept as the checked `T`.** The research left it for lack of 0.16 errors. 0.20 is the release that settles std's shapes before 1.0, and `v[i]` (0.17) now covers the checked read, so `get` can mean what Rust means.

## 3. Performance: benchmarks and targets

**The harness: bench/std/** (P0).
- Each benchmark is a triple: NAME.vl, NAME.rs (rustc `-C opt-level=3 -C codegen-units=1 -C panic=abort`, std only, no crates) and NAME.c (`cc -O2`, libc only; hand-written where libc has nothing).
- Each program makes its input in-process from a fixed xorshift seed. Text benchmarks make theirs from samples of the UCD, written by the generator into bench/std/data/ (generated, not checked in).
- All three print the same checksum, and the harness checks it.
- bench/std/run.sh prints each row's fastest of N runs and the ratios. bench/std/targets.txt gives each row's Rust and C targets.
- `--gate` fails on a ratio above its target by more than 10% (noise). `gate.sh --only bench` runs it on an idle aarch64-macos machine. x86_64 is not measured.
- **Fair Rust baselines.** Where Rust's default differs in algorithm (SipHash), the .rs file has two variants: Rust's default, and Rust's table with the same hash as ours (foldhash written into the .rs file, about 60 lines). The target binds against the second, so the comparison is between tables, not hash functions.

**Targets** (vole -O2 time divided by the baseline's; below 1 is faster):

| bench | operation | vs Rust | vs C | today | owner |
|---|---|---|---|---|---|
| hash_u64 | 2M inserts of random u64, 2M lookups (half hits) | ≤ 1.10 (same hash); ≤ 0.6 (Rust default) | ≤ 1.0 (hand linear probing) | 1.3 vs default | A2/B2 |
| hash_str | word count over 32 MB, `str` keys | ≤ 1.10 (same hash); ≤ 0.7 | ≤ 1.0 | 0.8 vs default | A2/B2 |
| hash_churn | 50% insert, 50% remove, 10M ops (tombstones) | ≤ 1.15 | – | – | A2/B2 |
| hash_iter | iterate 1M entries ×100 | ≤ 1.10 | – | – | B2 |
| btree_u64 | 1M random inserts, 1M lookups, 1000 range scans | ≤ 1.15 | – | none | A3/B3 |
| vec_push | 100M `push` of u64 with growth | ≤ 1.05 | ≤ 1.05 (realloc doubling) | – | B1 |
| vec_retain_dedup | retain half of 10M, dedup | ≤ 1.10 | – | none | A1/B1 |
| deque | 10M `push_back` + `pop_front`, ring of 1k | ≤ 1.05 | – | none | B4 |
| heap | 1M push then pop; Dijkstra on a 1000×1000 grid | ≤ 1.10 | ≤ 1.0 (hand heap) | none | A1/B4 |
| sort_unstable | 5M u64: random, sorted, reversed, 16 distinct values | ≤ 1.15 | ≤ 0.5 (qsort) | ≈4 | A1 |
| sort_stable | 5M u64; 2M (str key, i64) by key | ≤ 1.25 (driftsort) | ≤ 0.5 (mergesort) | ≈3.4 | A1 |
| sort_slice_noalloc | `s.sort()` on a slice, 1M u64 | ≤ 3.0 against Rust `sort` (documented) | – | – | A1 |
| bsearch | 10M lookups in 1M sorted u64 | ≤ 1.05 | ≤ 0.8 (bsearch) | – | A1 |
| utf8_validate | 64 MB each: ASCII, Latin-1 mixed, CJK, emoji | scalar ≤ 1.2; with 0.19 ≤ 0.5 on non-ASCII and ≥ 10 GB/s ASCII | – | none | A4/D2 |
| chars | `s.chars().count()` and the sum of code points, 64 MB mixed | ≤ 1.10 | – | none | A4/B5 |
| graphemes | segment 64 MB: ASCII, mixed, emoji-heavy | ≥ 1 GB/s ASCII, ≥ 150 MB/s mixed (no Rust std baseline) | – | none | A5 |
| width | `str::width` over 64 MB: ASCII, CJK | ≥ 2 GB/s ASCII scalar (≥ 4 with 0.19), ≥ 800 MB/s CJK | ≤ 0.3 (`mbrtowc` + `wcwidth`) | none | A5/D2 |
| fmt_f64 | Display of 1M random f64 into a String | ≤ 1.0 | ≤ 0.2 (`%.17g`) | 12.5 | A6 |
| fmt_f64_prec | `{:.3}` of 1M f64 | ≤ 2.0 (phase 1) | ≤ 1.0 | – | A6 |
| parse_f64 | parse 1M shortest f64 strings | ≤ 1.10 | ≤ 0.5 (`strtod`) | – | A6 |
| fmt_int / parse_int | 10M i64 each way | ≤ 1.05 | ≤ 0.5 (`snprintf`, `strtol`) | – | A6 |
| read_lines | 256 MB file, `BufReader::lines` | ≤ 0.8 (Rust allocates per line); ≤ 1.0 (Rust `read_line` into a reused String) | ≤ 1.0 (`getline`) | none | B6 |
| write_lines | 10M `writeln(out, f"{i} {x}")` to /dev/null | ≤ 1.0 (locked, `BufWriter`) | ≤ 1.0 (`printf`) | – | B6 |
| read_file | `fs::read_in` of 1 GB | ≤ 1.02 | ≤ 1.02 | none | B6 |
| spawn | 1000 × spawn `/usr/bin/true` and wait | ≤ 1.10 | ≤ 1.05 (`posix_spawn`) | none | B6 |
| rng | 10^9 `next_u64`; 10^8 `random_range` | ≤ 1.05 (the same algorithm written in Rust) | ≤ 1.05 | none | A7 |

**The terminal budget (0.23).** The parser's inner loop is: find the printable-ASCII run; otherwise decode UTF-8, step `GraphemeState`, look up the width. bench/std/term_feed runs that loop (A4 and A5 together) over three recorded streams: `cat` of source files, CJK text, and emoji-heavy chat logs. Targets, without allocation and with output identical to the per-call API:
- ≥ 1 GB/s on the source-files stream with scalar code, and ≥ 3 GB/s with 0.19;
- ≥ 400 MB/s on CJK;
- ≥ 150 MB/s on emoji.

Alacritty's `cat` throughput is far below these. The point is that text handling never shows in the terminal's profile.

**Compile time.** std grows by perhaps 15k lines and about 50 KB of tables, and it must not show up in programs that do not use it. With lazy sections and the tables in their own sections:
- a hello world compiles within +1 ms of today;
- a HashMap program within +3 ms;
- a program using `width()` or float parsing within +5 ms (the tables are lexed once).

Tables are emitted as byte-string literals, the densest form the lexer reads. If the +5 ms is missed, P0's fallback is a built-in data blob: the compiler emits the table bytes straight into the object, without lexing them. P0 measures it with the first generated table.

## 4. Work split

### 4.1 How work done now survives 0.17

Wave A is written in today's language (0.16 plus the familiar forms): `*T` parameters, writable `[T]`, explicit `free`. So that the 0.17 conversion is mechanical:

1. **Internal functions over storage.** Wave A provides functions over slices, raw storage and integers, plus private structs. It adds no public owning type: those are Wave B's, which adds Drop.
2. **Raw pointers** appear only in the raw-storage files and inside small `unsafe` blocks. A struct holding them, such as `RawTable` or a B-tree node, has a `free` method that becomes its Drop body (0.17's G8 rule).
3. **Views are passed down, never stored in statics.** An iterator state that holds a view (the grapheme iterator, the split state) is a struct with a `[u8]` field: legal now, and a view type under 0.17, which T4's `#[views]` pins name.
4. **Comparators and closures** take `*T` now, which `fix --values` turns into `&T`.
5. **Every task's code merges into main as soon as it is ready,** as private items (`pub(crate)`-like, unexported from std's public index). Each release gate from 0.17 to 0.19 then tests it. Its public API appears in 0.20. Two exceptions may ship early because their output is byte-identical:
   - A6's float and integer formatting, replacing `Fmt`'s C round trip;
   - A1's sorts, replacing today's `sort` and `sort_stable_in` with the same meaning.
6. **When 0.17 lands,** the lead runs `fix --values` over Wave A's files in one commit before Wave B starts.

### 4.2 Phase 0: the interface commit (can start now; the lead; serial; about 2 days)

- **std as a module tree.**
  - compiler/std/ gets subdirectories, and embed.sh and index.awk carry each file's module path.
  - The loader resolves `std::a::b::Item` and lazy sections per file.
  - `pub use` re-exports keep every 0.17 name at `std::NAME`.
  - The prelude list is extended, and new names are added as their items land.
- **Per-target tail.** `std_sys_tail` appends sys/macos.vl or sys/linux.vl, as `std_alloc_tail` does, plus the injected `std::TARGET_OS`.
- **Declarations with stub bodies (`unreachable()`)**, so that every task builds against fixed signatures:
  - `Ordering` (the enum and its methods);
  - `Hasher`, `BuildHasher` and `FixedState`;
  - `wide_mul`;
  - `Group`'s functions and `BitMask`;
  - `Utf8Error`, `io::ErrorKind`;
  - the sys signatures of §4.3 A7;
  - `GraphemeState`, `props()` and its bit masks;
  - the number-conversion entry points.
- **bench/std/:** run.sh, targets.txt, the fair-hash Rust helper, and the five programs of §1 as the first pairs.
- **tests:**
  - tests/std/ for new cases;
  - tests/std-model/, the before-0.18 model tester: a std-internal module with a seeded operation generator and a check-against-model loop. Wave A tasks write `model_*` cases with it, and C1 turns them into `#[property]` tests;
  - tests/std/oracle/, Rust oracle programs for byte-exact comparisons, skipped when rustc is missing.
- **The table-cost measurement** (§3, compile time): with a 24 KB dummy table, decide byte-string literals or the data blob.

### 4.3 Wave A: can start now

| task | owns | provides (interfaces) | depends |
|---|---|---|---|
| **A0 Ordering, Hash and Hasher** | compiler/std/cmp.vl; hash/mod.vl (the traits); compiler/src/front's derive of Ord and Hash; the `fix --only std020` rules for comparators and hand-written impls | `Ord::cmp -> Ordering`, `PartialOrd`, `Reverse`, `cmp_of -> Ordering`; `Hash::hash<H: Hasher>(self: *Self, state: *H)`; derive(Hash) as `state.write_*` per field; every std impl moved; `hash_of` through FixedState; the fix rules: comparator bodies `a - b` → `a.cmp(&b)`, otherwise `Ordering::from_i64(e)`; `fn hash(self) -> u64 { e }` → `fn hash<H: Hasher>(self, state: *H) { state.write_u64(e) }` | P0 |
| **A1 Slice algorithms and sorts** | compiler/std/slice/{sort_unstable,sort_stable,search,algo,heap}.vl | `sort_unstable_by<T, F: FnMut(*T, *T) -> Ordering>(s: [T], f: F)`; `sort_stable_by_with<T, F>(s: [T], scratch: *T, scratch_len: i64, f: F)` (scratch ≥ n/2 for O(n log n), smaller falls back to in-place merges); `binary_search_by(s, f: FnMut(*T) -> Ordering) -> Result<i64, i64>`; `partition_point`; `select_nth_unstable_by`; `heap_sift_up_by`, `heap_sift_down_to_bottom_by`; `reverse`, `rotate_left`, `rotate_right`, `fill`, `dedup_by(s, f) -> i64` (the new length), `retain_by(s, f) -> i64`, `shuffle(s, rng)`; bench pairs: sort_*, bsearch, heap (algorithm half) | A0 (Ordering) |
| **A2 Hashing and the raw table** | compiler/std/hash/{fold,sip,state}.vl; collections/raw_table.vl; collections/group.vl (scalar) | FoldHasher, FixedState, RandomState (its seed through A7's `sys::getentropy`, stubbed until A7 merges), SipHashState; `RawTable<T, A>` with `new_in`, `with_capacity_in`, `find(hash, eq: FnMut(*T) -> bool) -> i64`, `bucket(i) -> *T`, `insert(hash, x: T, hasher: FnMut(*T) -> u64) -> i64`, `erase(i)`, `take(i) -> T`, `reserve(n, hasher)`, `clear`, `iter() -> RawIter` (the next full index), `len`, `free`; the Group API of §2.4.2; the probe-length statistics (a test-only function); bench pairs hash_u64, hash_str, hash_churn (on RawTable, through a thin test map) | A0, P0 |
| **A3 The B-tree node core** | compiler/std/collections/btree_node.vl | leaf and internal nodes (`[K; 11]`, `[V; 11]`, `[*Node; 12]`, `parent`, `parent_idx`, `len`), allocated through a generic `A`; `search_tree(root, height, key: *K) -> Handle`, `insert_fit/split`, `remove_kv` with steal and merge, `first_leaf_edge`, `next_kv`, `next_back_kv`, `range_search`, `free_tree`; the bench pair btree_u64 (on a thin test map) | A0 |
| **A4 UTF-8 core** | compiler/std/str/utf8.vl | `validate_utf8(b: [u8]) -> Result<(), Utf8Error>`; `ascii_prefix_len`, `ascii_printable_prefix_len`; `decode_at(b, i) -> u64` (cp and length; valid input); `next_code_point`, `next_code_point_reverse`; `encode_utf8(cp: u32, out: *[u8; 4]) -> i64`; `count_chars`; `Utf8Decoder { state, pending }` with `feed(self, b: [u8], out: [u32]) -> (consumed, produced)` and `finish`; `decode_into`; `lossy_next`; boundary helpers; bench pairs utf8_validate, chars, the term_feed decode half | P0 |
| **A5 Unicode tables, graphemes, width** | tools/unicode/{gen.vl,fetch.sh,ucd.lock}; compiler/std/unicode/{tables.vl (generated), props.vl, grapheme.vl, width.vl, case.vl, class.vl}; tests/std/unicode/ | `props(cp: u32) -> u16` and its masks; `char_width(cp) -> i64` (-1 for a control), `char_width_cjk`; `GraphemeState::new()`, `push(self: *Self, cp: u32) -> bool`; `cluster_width(..)` (the §2.5.4 rule, fed code points); `is_alphabetic`, `is_numeric`, `is_whitespace`, `is_lowercase`, `is_uppercase`, `is_control`; `to_lower(cp) -> [u32; 3]`, `to_upper`; `UNICODE_VERSION`; bench pairs graphemes, width, term_feed | P0; A4 for the bench only |
| **A6 Numbers** | compiler/std/num/{wide,int_fmt,int_parse,flt2dec,dec2flt,tables}.vl; tools/numtables/gen.vl; fmt.vl's float and int paths (the early swap) | `wide_mul(a: u64, b: u64) -> (u64, u64)`; `fmt_u64(v, out: *[u8; 20]) -> i64` (the start index); `f64_shortest(v) -> (u64, i32)`, `f32_shortest`; `write_f64(v, mode, out: *[u8; 32]) -> i64` (Display, Debug, LowerExp, UpperExp); `parse_f64(s: [u8]) -> Result<f64, ParseFloatError>`, `parse_f32`; `parse_i64_radix`, `parse_u64_radix`; bench pairs fmt_f64, fmt_f64_prec, parse_f64, fmt_int, parse_int | P0 |
| **A7 The OS layer** | compiler/std/sys/{unix,macos,linux}.vl; compiler/std/time.vl (Duration); compiler/std/random.vl (the core); the layout test | every function `Result<T, i32>` with the effect `io`: `open(path: [u8], flags: i32, mode: i32) -> Result<i32, i32>` (the NUL copy inside), `read(fd, buf: [u8])`, `write`, `pread`, `pwrite`, `lseek`, `close`, `fstat`/`stat`/`lstat -> FileStat`, `mkdir`, `rmdir`, `unlink`, `rename`, `ftruncate`, `fsync`, `opendir`/`readdir_into(dir, name: *[u8; 256])`/`closedir`, `getcwd_into`, `chdir`, `pipe`, `dup2`, `fcntl_nonblock`, `spawn(prog, argv: [*u8], envp, actions) -> Result<i32, i32>` (`posix_spawnp`), `waitpid`, `kill`, `openpty`, `fork_exec_pty`, `poll`, `isatty`, `tcgetattr`/`tcsetattr`, `ioctl_winsize`, `clock_gettime(clock) -> (i64, i64)`, `nanosleep`, `getentropy(buf: [u8])`, `errno() -> i32`, `strerror_into`, `errno_kind(e) -> ErrorKind`, `argv()`/`environ()` access; Duration's arithmetic; `Xoshiro256pp`, `seed_from_u64`, `random_range_u64` (Lemire), `unit_f64`; bench pairs rng, the sys half of read_file and spawn | P0 |
| **A8 const generics (L1)** | compiler/src/front: generic parameters, instantiation keys, array-length substitution; docs/grammar.md's section; tests | `const N: i64` on structs, enums, impls and fns; `[T; N]`; inference of N from an argument's array type; a const argument written `Foo::<T, 4>`; mangling | none |
| **A9 `char` (L2)** | compiler/src/front: the type, its literal typing and casts; middle and back: a 4-byte integer with an `as` check; docs/grammar.md; tests | `char`; `'é'`; `b'a'`; `c as u32`, `u as char` only for `u8` (Rust's rule); `char::from_u32`; Display and Debug for char in fmt.vl (Rust's escapes for Debug) | none |

### 4.4 Wave B: needs 0.17 (".1": needs 0.17.1's projections)

| task | owns | provides | depends |
|---|---|---|---|
| **B1 Vec and slices on values** | compiler/std/collections/vec.vl (Vec moves out of std.vl); slice/mod.vl (the `[T]` and `&mut [T]` methods over A1) | §2.4.1: Drop, the `&self`/`&mut self` API, `iter`/`iter_mut` (.1), `get -> Option<&T>` (.1), `retain`, `dedup`, `drain`, `extend`, `into_iter`, `v.sort()` through its allocator; DoubleEndedIterator and ExactSizeIterator in iter.vl | 0.17 T4 (std on values), A1 |
| **B2 HashMap and HashSet** | collections/{hash_map,hash_set}.vl; the removal of std.vl's HashMap | §2.4.2's API over RawTable; `Borrow`; `entry` (.1); `iter`, `drain`, `retain`; Debug, Eq, Clone; the bench rows hash_* on the public map | A2, B1 |
| **B3 BTreeMap and BTreeSet** | collections/{btree_map,btree_set}.vl | the API over A3; `range` views; Drop (the iterative free) | A3, B1 |
| **B4 VecDeque, BinaryHeap, SmallVec, ArrayVec, BitSet** | collections/{vec_deque,binary_heap,small_vec,bit_set}.vl | §2.4.4; heap over A1's sift functions; bench rows deque, heap | B1, A8, A1 |
| **B5 Text** | compiler/src/front: `str` (L3), literal typing, the deref coercions; compiler/std/{str/mod,str/pattern,str/iter,string,char}.vl; fmt.vl (`format_in -> String`, `fmt::Write`, `{:e}`) | §2.5.1–2: `str` and its methods, `String`, char's methods over A5, `graphemes(true)`, `width()`, `Pattern`, `FromStr`/`parse` over A6, `ToString`, `Borrow<str>`; Scanner, `split_in` and `trim` re-based on `str`/`[u8]`, keeping their 0.17 names | A4, A5, A6, A9, B1 |
| **B6 I/O and the system API** | compiler/std/io/{mod,buffered,stdio,error}.vl (io.vl's content moves here); fs.vl, path.vl, env.vl, process.vl, os/unix.vl, time.vl (Instant, SystemTime), random.vl (the `Rng` API) | §2.6: `io::Error`, Read/Write/BufRead, `BufReader`/`BufWriter` with inline buffers, lending `lines()`, std streams with buffering, `fs`, `Path`/`PathBuf`, `env`, `process`, pty and poll, `Instant`, `Rng`; the main wrapper's argv and environ capture (compiler/src/front/ambient.vl); bench rows read_lines, write_lines, read_file, spawn | A7, B1, B5 (for `str` and `String`) |
| **B7 Tools, guide, migration, examples** | compiler/guide/{collections,text,io,std,rust}.md; tools: `fix --only std020` (beyond A0's rules), the explain entries, the guide's most-used list; docs/grammar.md (L3); examples/std/ (wordfreq on HashMap and String, a grep on BufReader and `str::find`, a `du` on read_dir, a pipeline on process); docs/releases.md | everything of §2.8 tested as `try:` lines (each `alloc.explicit` try runs in tests/std/try); `fix --only std020` over the corpus with same-output | everything; last |

### 4.5 Wave C: needs 0.18

| task | owns | provides |
|---|---|---|
| **C1 Properties, fuzzing, contracts** | tests/std-props/; the `invariant`/`requires` lines in the collection files (a small, separate commit per file, coordinated with its owner) | every tests/std-model case as a `#[property]` against its model (HashMap and HashSet against an association list, BTreeMap against a sorted Vec, VecDeque and BinaryHeap against Vec, String against Vec<char>, both sorts against insertion sort with stability by index, `Utf8Decoder` against the naive decoder, `GraphemeState` against the rule-by-rule oracle, `parse_f64` against strtod); `#[fuzz]` entry points for dec2flt, UTF-8 validation, the segmenter and BufReader's line splitting; invariants on RawTable, the B-tree, VecDeque and String |

### 4.6 Wave D: needs 0.19

| task | owns | provides |
|---|---|---|
| **D1 The SIMD Group** | collections/group_neon.vl (aarch64), group_sse2.vl (x86_64, built and compiled but not run, per the no-x86 rule); the selection by `std::arch::has` | the Group API on `uint8x8_t` (and SSE2's low 8 lanes); a test that inserts 10^6 keys with each Group and compares the control bytes and buckets bytewise against the scalar table; hash_* rows rerun |
| **D2 SIMD text and bits** | str/utf8_neon.vl; str/memchr.vl; unicode/width_neon.vl; the `wide_mul` and `count_ones` swaps | Keiser–Lemire validation, `ascii_prefix_len`, `ascii_printable_prefix_len`, `count_chars`, memchr/memrchr (for `find`, `split`, `lines`, BufRead), and a width fast path for ASCII runs, each tested equal to its scalar version on random and adversarial input; `wide_mul` through `std::arch`, `BitSet::len` through `count_ones` |

The scalar version comes first in every case. It is the fallback when a feature is missing at run time, and the oracle for the SIMD version. Only aarch64 is measured and run.

### 4.7 Merge order

1. **P0.**
2. **A0** (small; every other A task uses `Ordering` or `Hasher`).
3. **A1 to A9**, in any order, each when its tests and bench rows pass. They land on main during the 0.17, 0.18 and 0.19 cycles as private std items. A6 and A1 may switch `Fmt` and `sort` over early (§4.1, rule 5).
4. **0.17 ships:** the lead's `fix --values` commit over Wave A.
5. **B1.**
6. **B5's language part** (`str`, the coercions).
7. **B2, B3 and B4** in parallel.
8. **The rest of B5.**
9. **B6.**
10. **B7** runs throughout, with its `fix --only std020` pass and the guide last.
11. **0.18 ships:** C1.
12. **0.19 ships:** D1, then D2.
13. **0.20 release gate:** `gate.sh --release` plus `gate.sh --only bench` with every §3 target met, or, for a soft miss, listed in docs/releases.md with its cause.

**Conflicts to avoid:**
- A0 touches derive in compiler/src, and A8 and A9 touch the front end's types and generics. Those three rebase on whatever 0.17's front/own work has landed, and keep to their files: generics/instantiate, the lexer's char literals, check's literal typing.
- B5's `str` changes check's coercion code, which 0.17's views also touch. It goes after 0.17.1.
- Only B1 edits std.vl's Vec section, and only B2 edits its HashMap section.

### 4.8 What can start now, in one list

P0, A0, A1, A2, A3, A4, A5, A6, A7, A8, A9: eleven tasks, about 60% of 0.20's code by line count, and all of its hard algorithms. They can run on up to nine agents at once after P0 and A0.

## 5. Migration: `volec fix --only std020`

Run over the corpus (tests, examples, bench, the guide's examples, the eval starters and solutions), then `same-output` against the previous compiler. The rules:

1. **Comparators** (A0):
   - `|a, b| a.k - b.k` and `fn cmp` bodies that are a subtraction become `a.k.cmp(&b.k)`;
   - other `i64` comparators are wrapped as `Ordering::from_i64(e)`;
   - `cmp_of(..) < 0` becomes `cmp_of(..) == Ordering::Less`;
   - `sort(s)` becomes `s.sort_unstable()` (same meaning as before; R4).
2. **Hash impls** (A0): `fn hash(self: *T) -> u64 { e }` becomes `fn hash<H: Hasher>(self: *T, state: *H) { state.write_u64(e) }`, which keeps each hash's quality. Derived impls are regenerated.
3. **Vec access** (B1): `v.get(i)` (the checked `T`) becomes `v[i]`, and `v.set(i, x)` becomes `v[i] = x`.
4. **Maps** (B2):
   - `m.get_or_insert(k, d)[0] op= x` becomes `*m.entry(k).or_insert(d) op= x`;
   - `m.get_mut(k)` as `Option<[V]>` with `[0]` becomes `Option<&mut V>` with `*`;
   - the `slots`/`key_at`/`value_at` loop becomes `for (k, v) in m.iter()`, when the loop's body uses only those calls.
5. **Text** (B5): `format_in(..)` results used with `.as_slice()` become `.as_str()` (or `.as_bytes()` where a `[u8]` is needed). Bufs passed where text is expected keep working through `[u8]`.
6. **I/O** (B6): patterns on `IoError::Read` or `IoError::Write` become `e.kind()` comparisons. `IoError` becomes `io::Error`.

Iteration order of maps changes with the new hash and table. Expected outputs that print maps are regenerated once, in B2's commit, and listed in its message. This is the release's only intended output change.

## 6. Risks

- **0.17 slips, or 0.17.1's projections slip.** Wave A is unaffected. Wave B without projections keeps today's shapes for the affected items: `get` returns a copied `Option<T>`, `get_mut` returns `Option<[V]>`, and there is no `entry` and no `iter_mut`. B7 then marks those rows of §2.8 as pending. Nothing else in Wave B needs projections.
- **Table lexing cost.** P0 measures it first. The data blob is the fallback.
- **Determinism across Group implementations.** The bytewise test of D1 is the guard. A mismatch means a bug, not a choice.
- **The breaking changes:** `Ordering`, `Hash`, stable `sort`, `get`, `format_in -> String`, literal typing. Each has a `fix` rule and goes through same-output over the corpus. The literal typing (L2, L3) keeps today's meaning wherever a program compiles today, by design. That claim is tested by compiling the corpus before and after with no `fix` applied.
- **Confusion between Buf, String, `[u8]` and `str`.** The guide's text topic opens with the four-row table of §2.5.1. `str → [u8]` is free and implicit, so the confusion shows up as a missing method at worst, and 0.17's nearest-name help names the other type's method.
- **Unicode churn.** The lock pins the version. A yearly update is a regenerate-and-test commit.
- **Breadth.** 0.20 is the largest std release. It may split into 0.20 (collections and text) and 0.20.1 (I/O and the system), as the roadmap allows. Wave A makes that split cheap: B6 is the only Wave B task with no other task depending on it.

## 7. Open questions, with recommendations

Every one was taken as recommended, because the user is away and said to proceed through 0.23. They are listed again under "Decisions taken".

- **W1. Text types.** (A) `String` plus `str`, distinct from `Buf` and `[u8]`; (B) `String` as an alias of `Buf`, and `[u8]` for views; (C) no new types. *Recommended: A* (§2.5.1, §2.9).
- **W2. String literal and char literal typing.** Context-typed with today's defaults (`"x"` a `str` that coerces to `[u8]`; `'x'` a `u8` when ASCII), against Rust's fixed types. *Recommended: context-typed.* No program changes meaning, and Rust's forms all work.
- **W3. The default hasher.** (A) foldhash with a fixed seed, plus RandomState and SipHashState opt-ins; (B) Rust's random SipHash. *Recommended: A*, for determinism, effects and speed.
- **W4. The group width.** 8 on every target, so iteration order is target-independent. *Recommended: 8.*
- **W5. `sort` semantics.** `sort` becomes stable (Rust's meaning), with the Vec form using the Vec's allocator and the slice form a stack buffer plus in-place merges. Old uses become `sort_unstable`. *Recommended: yes.*
- **W6. `Ordering` and `Hasher`**, Rust's shapes, in A0 now. *Recommended: yes.*
- **W7. `Vec::get -> Option<&T>`** (Rust's) in 0.20, with `fix` rewriting old uses to `v[i]`. *Recommended: yes.*
- **W8. Inline buffers** in `BufReader`, `BufWriter` and `Command`, so that Rust's constructors do not need allocators. *Recommended: yes.*
- **W9. Float formatting.** Schubfach (A), Ryu, Dragonbox, or Grisu with Dragon4. *Recommended: Schubfach*, with Dragonbox behind the same interface if needed later. Parsing uses Eisel–Lemire with the simple-decimal fallback. `{:.N}` stays on libc in phase 1.
- **W10. Display width.** Both per code point (unicode-width's, Alacritty's) and per grapheme (mode 2027), the terminal choosing. *Recommended: both.*
- **W11. The OS layer.** libc on both targets, hand-written bindings with a layout test, per-target std files, no `#[cfg]` yet. *Recommended: yes.*
- **W12. Random.** rand 0.9's names (`random_range`, `seed_from_u64`) on xoshiro256++, in `std::random`. *Recommended: yes.*
- **W13. Const generics (L1)** in 0.20, for `SmallVec`, `ArrayVec` and array impls. *Recommended: yes*, as A8, now.
- **W14. Wave A merges early as private std items**, with the formatting and sort swaps allowed to ship in 0.17 to 0.19 when their output is byte-identical. *Recommended: yes.*
- **W15. The generator is written in vole.** *Recommended: yes* (dogfooding). Python would be quicker to write, but adds a second language to the release chain.

### Critical files for implementation

- compiler/std/embed.sh, compiler/std/index.awk, compiler/src/front/modules/stdsections.vl (`load_std_sections`, `read_index`) and compiler/src/front/modules/mod.vl (`load_std_if_named`): std as a module tree, lazy per file (P0).
- compiler/src/front/stdalloc.vl (`std_alloc_tail`): the model for `std_sys_tail` and `TARGET_OS` (P0).
- compiler/std/std.vl: `HashMap` (`slot_of`, `insert_new`, `rehash`), `sort` and `quicksort`, `sort_stable_in`, the `Hash`/`Ord`/`Eq` impls, `hash_u64`. These are what A0, A1, A2, B1 and B2 replace.
- compiler/std/clone.vl (`hash_mix`, `hash_of`, `cmp_of`) and compiler/src/front's derive (`derive(Hash)`, `derive(Ord)`): A0.
- compiler/std/fmt.vl (`fmt_float`, `Fmt::int`, `format_in`): A6's swap, then B5.
- compiler/std/io.vl (`read_line`, `read_stdin_in`, `Scanner`, `IoError`): moves under std::io (B6), re-based on `str` (B5).
- compiler/src/front/ambient.vl (`main_gpa`): where B6 captures argv and environ.
- bench/run.sh: the model for bench/std/run.sh (P0).

## Decisions taken (for the user's review)

Taken on 2026-10-16, as recommended, because the user is away and said to work through 0.23. Each can be revisited. Changing any of D1 to D7 after Wave B starts costs a migration.

- **D1 (W1). Text types:** `String` (owned UTF-8) and `str` (a UTF-8 view) are new and distinct. `Buf` and `[u8]` stay as the byte types. `str` coerces to `[u8]` for free. `format_in` returns `String`.
- **D2 (W2). Literal typing:** `"x"` is a `str` coercing to `[u8]`, and `'x'` is context-typed, `u8` by default when ASCII. `b'x'` is accepted. `s[i]` on a `str` reads a byte. Today's programs keep their meaning.
- **D3. Naming rule:**
  - Rust's names and shapes wherever nothing allocates implicitly (R1);
  - an `_in(.., a)` form plus an `alloc.explicit` error with `try:` where Rust allocates (R2);
  - non-allocating implementations under Rust's names where Rust allocates only incidentally (R3);
  - false friends fixed (R4).

  std gets Rust's module paths, and the prelude adds the collections, the text types, `Ordering`, `Reverse` and the I/O traits.
- **D4 (W3, W4). Hashing:**
  - foldhash with a fixed seed by default, so iteration order is deterministic;
  - `RandomState` and `SipHashState` as opt-ins for untrusted input;
  - a Swiss table (hashbrown's layout), load 7/8, tombstones, in-place rehash;
  - group width 8 on every target and implementation;
  - `Hash`/`Hasher`/`BuildHasher` in Rust's shape.
- **D5 (W5, W6). Ordering and sorting:**
  - `Ordering` replaces `i64` comparisons;
  - `sort` is stable (a Vec sorts with its own allocator, a slice with a stack buffer and in-place merges);
  - `sort_unstable` is ipnsort-like;
  - the stable sort is powersort-merge first, with driftsort's lazy runs only if the bench requires them;
  - old `sort(s)` calls become `sort_unstable`.
- **D6 (W7). `Vec::get -> Option<&T>`** in 0.20, with old uses rewritten to `v[i]`. The entry API replaces `get_or_insert`, and `iter()` replaces `slots`/`key_at`/`value_at` (deprecated one release).
- **D7. `io::Error`** is a kind, an OS code and a static message, with no allocation. `IoError` is a deprecated alias for one release. `BufRead::read_line` has Rust's meaning, and the free `read_line` keeps 0.15's.
- **D8 (W8).** `BufReader`, `BufWriter` and `Command` keep their buffers inline (8 KB, 32 arguments). `lines()` is a lending iterator of views. `env::args()` yields `str` views of argv.
- **D9 (W9). Numbers:**
  - Schubfach for shortest float formatting (Display and Debug byte-identical to Rust's), plus `{:e}`;
  - Eisel–Lemire with the simple-decimal fallback for parsing;
  - `{:.N}` on libc in phase 1;
  - itoa-style integer formatting;
  - `wide_mul` scalar now and an intrinsic in 0.19.
- **D10 (W10). Unicode:**
  - pinned UCD files and a vole generator, with generated tables checked in;
  - one `props()` trie (at most 24 KB) for the grapheme property, width class and the emoji and InCB bits;
  - UAX #29 graphemes through an incremental `GraphemeState`;
  - width both per code point (unicode-width's semantics) and per grapheme.
- **D11 (W11). The OS layer:** hand-written libc bindings per target, with a layout test against the headers; per-target std files selected by the compiler; no raw syscalls; no `#[cfg]` in 0.20. Paths are bytes and are copied to a stack buffer for C. The pty support 0.23 needs is in `std::os::unix`.
- **D12 (W12). Random:** `std::random::Rng`, xoshiro256++, with rand 0.9's method names. Deterministic seeding is pure, and entropy is `io`.
- **D13 (W13). Language additions:** const generic parameters (A8) and `char` (A9) start now. `str` and the deref coercions (B5) come after 0.17.1. No `u128`.
- **D14 (W14, W15). Process:**
  - Phase 0, then Wave A (P0 and A0 to A9, eleven tasks) starts now and merges into main as private std items as it is ready;
  - the float-formatting and sort swaps may ship early when their output is byte-identical;
  - Wave B (B1 to B7) after 0.17, Wave C (C1) after 0.18, Wave D (D1 and D2) after 0.19, scalar first in every case;
  - 0.20 may split into 0.20 (collections and text) and 0.20.1 (I/O) if B6 runs late.
- **D15. Performance gate:** every §3 row has a bench/std triple (vole, Rust std, C), with targets in bench/std/targets.txt, and `gate.sh --only bench` fails on a hard miss. Programs that do not use the new std must not compile slower (+1 ms for a hello world).
