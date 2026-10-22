# vole 0.25 design: compile speed

The user's goal: a self-compile in 100 ms or less. This document is the
baseline of v0.24.0, where the time goes, what bounds the goal, and the
0.25 tasks.

Measured on branch perf25 at f7a3d1d6 (vole 0.24.0), built with
`bootstrap/bootstrap.sh --dev`. Host: Apple M5, aarch64-macos, 10 cores
(4 performance, 6 efficiency), idle (load average under 3, no other
agent). Nothing but this file was changed.

## 1. Method

- **The compiler:** `target/volec` (v0.24.0, built by v0.24.0 at -O2).
  **The input:** `compiler/src/main.vl`: 399 files and 188k lines in
  compiler/src, plus the std sections it reads from the embedded std
  (compiler/std is 48k lines, 1.8 MB). That is 10.8 MB of source.
- **No cache:** `VOLE_CACHE=off VOLE_CODE_CACHE=off`, except in the
  incremental and `query (tools cache)` rows.
- **Each row:** 7 runs.
  - Wall: the best run, `perf_counter` around `/usr/bin/time -l`, which
    adds about 2 ms.
  - Instructions retired and peak RSS: the fewest of the 7, from
    `/usr/bin/time -l`.
  - User and system time: those of the best run.
- **The phases:** `--time-passes` gives CPU time on one thread, and
  `VOLE_PHASE_TIMES=1` gives the wall time at each -j.
- **The functions:** `/usr/bin/sample` at 1 ms, attached to a process
  spawned suspended (`posix_spawn` with `POSIX_SPAWN_START_SUSPENDED`), so
  nothing is missed at the start.
  - Runs aggregated: 10 runs of -O0 -j1, -O0 -j8 and `check`; 5 runs of
    -O1 -j1, -O2 -j1 and `query refs`; 25 runs of std_heavy.
  - `sample` takes about 0.82 samples per ms of wall time. Sampled
    milliseconds are scaled to wall time (×1.24 for the -O0 self-compile).
- **Allocations:** a `DYLD_INSERT_LIBRARIES` interposer counts malloc,
  calloc, realloc and their bytes, and takes a snapshot at each
  `VOLE_PHASE_TIMES` line.

## 2. Baseline (v0.24.0)

Self-compile. "link" means `-o` (an executable, through `sh -c 'cc ...'`);
"-c" means an object only.

| run | wall | user + sys | instructions | peak RSS |
|---|---|---|---|---|
| -O0 -j8 (default), link | **507 ms** | 550 + 50 ms | 11.36 G | 431 MB |
| -O0 -j1, link | 571 ms | 560 + 50 | 11.33 G | 411 MB |
| -O0 -j8, -c | **474 ms** | 500 + 30 | 11.37 G | 432 MB |
| -O1 -j8, link | 598 ms | 1410 + 80 | 18.25 G | 609 MB |
| -O1 -j1, link | 1153 ms | 1120 + 60 | 18.19 G | 616 MB |
| -O1 -j8, -c | 567 ms | 1370 + 60 | 18.27 G | 608 MB |
| -O2 -j8, link | 1040 ms | 3680 + 120 | 44.74 G | 856 MB |
| -O2 -j1, link | 2839 ms | 2770 + 80 | 44.60 G | 835 MB |
| -O2 -j8, -c | 1004 ms | 3620 + 90 | 44.74 G | 856 MB |
| `check compiler/src/main.vl` | **296 ms** | 260 + 20 | 5.58 G | 310 MB |
| `query refs buf_new --count`, no cache | **705 ms** | 670 + 20 | 18.32 G | 420 MB |
| `query refs buf_new --count`, tools cache warm | 21 ms | 10 + 0 | 0.20 G | 52 MB |
| incremental -O1: cold, cache on | 621 ms | 1470 + 90 | 18.73 G | 648 MB |
| incremental -O1: warm, nothing changed | 555 ms | 600 + 90 | 10.03 G | 638 MB |
| incremental -O1: one function edited | **561 ms** | 590 + 90 | 10.09 G | 645 MB |
| incremental -O2: cold, cache on | 1127 ms | 4030 + 140 | 48.06 G | 977 MB |
| incremental -O2: warm, nothing changed | 722 ms | 980 + 140 | 13.57 G | 998 MB |
| incremental -O2: one function edited | **730 ms** | 970 + 150 | 13.66 G | 998 MB |

The one-function edit changes the literal in
`middle::parallel::threads_for` (`functions / 16 + 1`) on a copy of
compiler/src. Each run's edit differs from the run before.

Small programs:

| run | wall | instructions | peak RSS |
|---|---|---|---|
| hello world, -O0, link | 32.7 ms | 0.10 G | 37 MB |
| hello world, -O0, -c | 7.8 ms | 0.10 G | 17 MB |
| hello world, -O2, link | 32.4 ms | 0.10 G | 37 MB |
| `check` hello world | 7.3 ms | 0.09 G | 18 MB |
| tests/cost/std_heavy.vl, -O0, -c | 41.9 ms | 1.15 G | 56 MB |
| tests/cost/std_heavy.vl, -O2, link | 67.3 ms | 1.15 G | 56 MB |

The link, measured on its own (best of 9):

| | self object (9.0 MB) | hello object |
|---|---|---|
| `sh -c 'cc -arch arm64 -o x obj'` (what volec runs) | 34.3 ms | 23.8 ms |
| `cc` without the shell | 31.7 | 21.2 |
| `ld` alone (`-syslibroot`, `-lSystem`) | 28.0 | 17.6 |

`ld`'s flags (`-no_uuid`, `-no_adhoc_codesign`, `-ld_classic`,
`-no_deduplicate`) change nothing. About 17 ms of `ld` is a fixed cost,
mostly reading libSystem's stubs, and about 11 ms is the size of the
self object. **A hello world spends 75% of its 33 ms in the linker.**

## 3. Where the time goes

### 3.1 -O0 -j8 -c (474 ms): the main thread is the critical path

The breakdown comes from the samples, scaled to the wall time.

| phase | ms | notes |
|---|---|---|
| **module loading** (`load_modules`, before `compile_program`) | **103** | missing from `--time-passes` and `VOLE_PHASE_TIMES` |
| — lexing (`lex_range`) | 63 | 10.8 MB at about 170 MB/s |
| — reading the files (399 `fopen`s) | 8 | |
| — `arch::virtual::load_arch_modules` | 14 | 3 scans of every token, `in_use_line`; the compiler's own `crate::arch` loads the intrinsic tables |
| — std sections (`load_std_sections`, `know_program`) | 12.5 | |
| parsing (`parse_program`) | 23.5 | |
| **checking** (`check_program`) | **167** | |
| — `modules::lookup::collect_uses` (resolve) | **64** | quadratic: each `use` name is compared with every earlier use entry of the program |
| — function bodies (`check_function_recovering`) | 53 | type checking |
| — collecting names, functions, statics and impls | 10 | resolve |
| — own (value semantics) | 13 | |
| — distinct types erased (`erase_all_types`, `erase_view_distincts`) | 11 | |
| — effects | 6 | |
| — features (`check_features`) | 5.5 | |
| code generation (gen0 from the syntax tree, as text) | 65 | |
| waiting for the assembler thread (`pthread_join`) | **59** | that thread assembles for 124 ms beside gen0's 65 |
| data (`gen_data`: `.byte` text, 16 decimal bytes a line) | 27 | 2.9 MB of constants, mostly the embedded std, become 12 MB of text |
| object (`write_object`: the data text assembled, fixups) | 21 | |
| Mach-O writing | 6 | |
| link (`-o`) | +33 | `sh` → `cc` → `ld` |

Rolled up:
- **The front end (load, parse, check) takes 294 ms, all of it serial.**
- The code generator takes 65 ms, serial.
- Assembly takes 124 ms on its own thread, of which 59 ms is exposed.
- Data and object writing take 54 ms, serial.
- The link takes 33 ms.

**The assembly text** is 54 MB in 2.2M lines for 7.5 MB of machine code,
about 25 bytes of text per instruction. gen0 writes it and the assembler
parses it back. In the assembler, `split_operands`, `parse_operand`,
`asym` and `directive` are the top of the profile.

At -j1 the same work is 571 ms with the link: the assembler runs inline
instead of on its own thread.

### 3.2 `check` (296 ms)

`check` is the front end above, with the same proportions:

| share | phase |
|---|---|
| 33% | loading (22% of it lexing) |
| 21% | `collect_uses` alone |
| 18% | function bodies |
| 8% | parsing |
| 5% | arch |
| 4% | own |
| 4% | std sections |
| 4% | type erasure |

### 3.3 `query refs`, no cache (705 ms); the LSP's first request (about 710 ms)

| share | what |
|---|---|
| **37%** | **`base::diag::buf_position`**, reached through `err_end` from `check_unchecked` |
| 10% | `collect_uses` |
| the rest | the front end |

A query checks the generic functions that were never instantiated, and
the bodies that failed. The checker formats an error for each problem it
finds there, then forgets the error. `buf_position` counts lines from the
start of the file for every error, so the cost is quadratic in the file's
length. `check_unchecked` also has a quadratic loop: `for g in 0..fns`
for each generic function.

### 3.4 -O1 and -O2 (wall at -j8 from `VOLE_PHASE_TIMES`, -j1 in parentheses)

| phase | -O1 | -O2 |
|---|---|---|
| module loading (not printed) | ~100 | ~100 |
| front end | 199 | 200 |
| lowering | 59 | 60 |
| cleanup | 15 (22) | 15 (21) |
| small leaves / scalar pipeline | 21 | 50 (265) |
| interprocedural constants, components | — | 51 |
| components, bottom up | — | 310 (1325) |
| dead functions | — | 34 |
| emission, join and assembly | 125 (677) | 133 (702) |
| data and output | 57 | 59 |

The serial part at -j8:
- -O1: about 440 of 567 ms.
- -O2: about 540 of 1004 ms.

Each pass's CPU time at -O2 -j1 (`--time-passes`, ms):

| pass | ms | pass | ms |
|---|---|---|---|
| loop passes | 724 | inlining | 422 |
| register allocation and emission | 388 | scalar pipeline | 264 |
| data and output | 145 | instruction selection | 99 |
| licm | 88 | lowering | 59 |
| interprocedural constants | 49 | global dead code | 34 |
| SLP | 24 | scalar promotion | 20 |
| attribute inference | 14 | heap to stack | 13 |
| tail recursion | 5 | | |

The IR is 152 MB as lowered and 276 MB optimized.

At -O2 the top functions by self time are spread thin:

| share | function |
|---|---|
| 6.2% | `ir_resolve_operands` |
| 4.6% | `IntVec.push` |
| 2.6% | `build_users` |
| 2.3% | `eliminate_dead_code` |
| 2.3% | `find_escaping_slots` |
| 2.2% | `compute_dominators` |

### 3.5 Incremental rebuilds

A warm -O1 rebuild after a one-function edit takes 561 ms, against 598 ms
cold. The code cache saves the middle end, but the front end (about
300 ms) and the serial phases around it remain. At -O2 the cache saves
more: 730 against 1040 ms. **The front end is the floor of every rebuild
and of the LSP.**

### 3.6 Small programs

Most of a hello world is the link: 33 ms in all, 7.8 ms with `-c`.

std_heavy -O0 -c (42 ms) is mostly std:

| ms (sampled) | what |
|---|---|
| 7 | std sections |
| 5 | arch tables (`load_table`'s `split_fields`, and `in_use_line`) |
| 3 | parsing |
| 8.5 | checking |
| 2.5 | gen0 |
| 3.6 | assembly |

A line count from the start of the file shows up here as well:
`closures::file_lines` takes 3%, and `contracts::sites::starts_upto` 2.3%.

### 3.7 Allocations (the interposer, -j1)

| phase | malloc | realloc | bytes allocated | realloc growth |
|---|---|---|---|---|
| front end (load, parse, check) | 106k | 2.7k | 39 MB | 321 MB |
| -O0 gen0, data and output | 108k | 0.6k | 6 MB | 120 MB |
| -O1 lowering | 0.7k | 321k | 2 MB | 373 MB |
| -O1 emission, join and assembly | 362k | 972k | 96 MB | 643 MB |
| -O2 scalar pipeline | 190k | 165k | 48 MB | 147 MB |
| -O2 bottom-up | 363k | 2.18M | 132 MB | 1212 MB |
| -O2 emission | 223k | 1.13M | 83 MB | 782 MB |
| **total -O0 / -O1 / -O2** | 214k / 496k / 889k | 3.3k / 1.3M / 3.8M | 45 / 144 / 308 MB | 0.44 / 1.4 / 2.9 GB |

The front end is not bound by malloc: about 100k calls take about 3 ms.
Its cost is the growth of a few big tables by realloc (`TOKS`, `NODES`,
`SRC`; `memmove` is 3.9% of -O0) and their size:
- a `Token` is 48 bytes;
- a `Node` is 18 words;
- 430 MB of RSS is 30k page reclaims (16 KB pages), which cost about
  30 to 40 ms of system time and zeroing.

The middle and back ends make millions of `IntVec` reallocations, so
arenas help there, at -O1 and -O2, and not at -O0.

### 3.8 Top 30 functions by self time

-O0 -j1 (10 runs, 4383 samples):

| % | function | % | function |
|---|---|---|---|
| 12.0 | front.modules.lookup.collect_uses | 1.4 | front.check.distinct.erase_all_types |
| 6.2 | back.objfile.assemble.split_operands | 1.4 | back.enc_arm64.operands.parse_reg |
| 6.2 | base.buf_uint (gen_data's `.byte` text) | 1.4 | front.modules.stdsections.know_program |
| 3.9 | _platform_memmove (realloc) | 1.3 | front.lexer.lex_ident |
| 2.7 | back.enc_arm64.operands.parse_operand | 1.2 | base.buf_byte |
| 2.2 | back.objfile.assemble.assemble_line | 1.1 | front.modules.child_module (linear scan) |
| 2.1 | front.lexer.peek_at (not inlined; reads statics) | 1.1 | base.buf_reserve |
| 2.0 | back.enc_arm64.a64_instruction | 1.0 | front.modules.module_at |
| 1.9 | back.objfile.asym | 1.0 | _platform_strlen |
| 1.7 | back.objfile.assemble.directive | 1.0 | front.lexer.is_whitespace (not inlined) |
| 1.7 | front.lexer.push_token | 1.0 | front.lexer.skip_whitespace_and_comments |
| 1.5 | _platform_memchr | 1.0 | arch.virtual.load_arch_modules |
| 0.9 | __open_nocancel | 0.9 | front.check.temps.visit |
| 0.9 | gen0.gen.call.gen_call_sequence | 0.9 | back.enc_arm64.is_simd |
| 0.9 | front.lexer.strings.lex_string | 0.9 | front.lexer.lex_token |

`check` (10 runs, 2429 samples):

| % | function | % | function |
|---|---|---|---|
| 21.2 | front.modules.lookup.collect_uses | 1.2 | front.features.regions.walk |
| 3.6 | front.lexer.peek_at | 1.2 | front.lexer.lex_token |
| 3.3 | front.lexer.push_token | 1.1 | front.own.drops.visit_temps |
| 2.8 | front.lexer.lex_ident | 1.1 | front.lexer.skip_whitespace_and_comments |
| 2.8 | front.check.distinct.erase_all_types | 1.0 | middle.lower.ssa.HMap.get |
| 2.7 | front.modules.child_module | 1.0 | base.intern |
| 2.6 | front.modules.stdsections.know_program | 1.0 | front.distinct.erase_type |
| 2.2 | _platform_memmove | 0.9 | base.IntVec.push |
| 2.1 | front.modules.module_at | 0.9 | tools.query.positions.find_name |
| 2.0 | arch.virtual.load_arch_modules | 0.8 | front.lexer.two_char_operator |
| 1.9 | __open_nocancel | 0.8 | front.check.temps.visit |
| 1.9 | front.ast.new_node | 0.7 | front.effects.infer.walk |
| 1.6 | front.lexer.strings.lex_string | 0.7 | front.parser.at |
| 1.6 | front.lexer.is_whitespace | 0.7 | front.check.lookup_local |
| 1.4 | base.buf_byte | 0.7 | front.lexer.is_alpha |

The lexer's small functions together take 16.7% of `check` (about
50 ms). Hashing and interning are not hot: `intern` takes 1%, and the
`HMap`s 1%.

## 4. What bounds 100 ms

Today's -O0 self-compile is **474 ms** (-c) and **507 ms** linked. For
100 ms, every part must fit:

| part | today | budget for 100 ms | what it takes |
|---|---|---|---|
| front end (load, lex, parse, check) | **294 ms, serial** | ≤ 45 | the quadratic scans fixed, a faster lexer, **and a parallel front end** (per-file lex and parse; per-module or per-function checking) or a cached checked form |
| code generation | 65, serial | ≤ 20 | gen0 parallel per function (it reaches the checker lazily: its statics are not per thread) |
| assembly | 124 on a thread, 59 exposed | ≤ 10 | instructions encoded directly as bytes, with text only for `-S` |
| data and object | 54 | ≤ 8 | data written as bytes, not `.byte` text |
| link | 33 | ≤ 8 | an in-house Mach-O linker. `ld`'s fixed cost alone is 17 ms |
| memory | 430 MB, 30k faults, about 35 ms of the above | ≤ 150 MB | smaller `Token` and `Node`, tables sized up front |

**What bounds the goal:**
1. **The serial front end.** Alone it is three times the budget. Even
   after this release's fixes (§5) it stays at about 180 ms, serial.
2. **The text assembly round trip.** gen0 writes 54 MB of text and the
   assembler parses it back.
3. **The system linker,** at 33 ms with a fixed 17 ms.

A 100 ms cold self-compile is therefore a goal for two or three
releases, and needs:
- a parallel front end (0.26);
- direct binary emission (0.26 or 0.27);
- an in-house linker.

A 100 ms *rebuild* after a small edit needs an incremental front end
(only the changed modules lexed, parsed and checked again; the rest from
a cache), which is also what takes the LSP's 710 ms away.

-O2 at 1.0 s is out of reach of 100 ms. Its serial part, at about
540 ms, is the front end plus lowering, interprocedural constants, dead
functions and data. Its CPU time is spread over passes, the largest being
the loop passes at 724 ms and inlining at 422 ms.

## 5. Opportunities, ranked

Savings are wall ms on the -O0 -j8 self-compile unless said otherwise.

| # | opportunity | saving | risk | notes |
|---|---|---|---|---|
| 1 | `collect_uses`: the duplicate-import check by a per-module set, not a scan of every use entry | **−64** -O0/-O1/-O2, **−62 `check`** (21%), −70 query | very low | one loop, `front/modules/lookup.vl`. `child_module` (a linear scan over about 500 modules, −5) by a hash in the same task |
| 2 | positions by a line index (each file's line starts, binary search) for `buf_position`, `closures::file_lines` and `contracts::sites::starts_upto`. Errors that `check_unchecked` forgets are not formatted at all. `check_unchecked`'s `for g in 0..fns` becomes a set | **−260 cold query and LSP** (37%), −5 to −10 -O0, −2 std_heavy | low | `base/diag.vl`, `front/check/mod.vl`, `front/closures/`, `front/contracts/sites.vl` |
| 3 | data written as bytes: `gen_data` makes 12 MB of `.byte` text from 2.9 MB of constants, and the assembler reads it back. Bytes go straight into the section when writing an object; `-S` keeps the text | **−40** -O0 (gen_data 27 and the data text's assembly 16), −25 to −35 -O1/-O2 ("data and output" 57) | low to medium | `gen0/target.vl` (`data_bytes`, `data_string`), `back/objfile/mod.vl` (`write_object`). Byte identity of the objects is checkable |
| 4 | the lexer: a local cursor instead of the static `LEX_POS` read and written per byte; `peek_at`, `is_whitespace` and `is_alpha` inlined, or a class table; `TOKS` sized from the source length | **−35** (lexing 63 → about 25), −30 `check` | low | `front/lexer/{mod,strings}.vl`. `--tokens` output identical over the corpus |
| 5 | arch loading: one scan of the tokens, not three. The compiler's own `crate::arch` must not count as std's `arch`. `load_table` parses its text at every compile, so precompute it | −12 self, −5 std_heavy (12%) | low | `arch/virtual.vl`, `arch/table.vl` |
| 6 | a faster text assembler: operands split once, register and mnemonic lookups by a perfect hash, `asym` by a better table | −59 at -O0 -j8 (the join's wait, if the assembler drops from 124 to about 65), −30 to −60 -O1 (the join assembles on one thread) | medium | `back/objfile/assemble.vl`, `back/enc_arm64/*`; `asym` is in `back/objfile/mod.vl` (P3's file), so its table changes after P3 merges, or `refactor move` it into assemble.vl first. A stepping stone towards #10 |
| 7 | the link without `sh` and the clang driver: `posix_spawn` of `ld` with the SDK path (cached) and the platform version | −6 on every linked build (hello 33 → 27) | low | `back/objfile/output.vl`. Falls back to `cc` for C files and `$VOLE_CC` |
| 8 | an in-house Mach-O linker for programs made of vole objects only (libSystem imports, ad hoc code signature) | **−28** self, **−20 of a hello world's 33 ms** | medium to high | `back/objfile/link_macho.vl` (new). Behind `--linker=self` until it passes the suite; falls back to `ld` |
| 9 | tables sized up front (`TOKS`, `NODES`, `SRC` from the source size), and a smaller `Token` (48 → 24 bytes: 32-bit start and length, kind and joint packed) | −10 to −20 (realloc copies, page faults), −80 MB RSS | low (sizing); medium (`Token`) | `front/lexer`, `front/ast.vl`. A smaller `Node` is the larger win, but it touches every `NODES[x].field` |
| 10 | direct binary emission from gen0 and back/emit (the encoder called with operands, not text) | −120 CPU at -O0 (the assembler and most of gen0's formatting), −60 wall at -O1 | high | `gen0/arm64.vl`, `gen0/x86_64.vl`, `back/emit/*`. Multi-day; 0.26 |
| 11 | parallel lexing and parsing per file (per-thread tokens and nodes, concatenated; intern under a lock or merged) | −70 (load and parse, 125 → about 30 at -j8) | medium to high | `front/modules/mod.vl`, `front/parser/*`, `base` intern. Conflicts with #4. Second wave or 0.26 |
| 12 | parallel checking of function bodies (`check_function`: 53, own 13, effects 6) | −50 | high | the checker's statics (types, instances) are global: a design first |
| 13 | an incremental front end: a module's tokens, nodes and checked facts cached by its hash, with only changed modules rechecked. **This is caching std's checked form for small programs, too** | rebuild 561 → about 250 at -O1; LSP 710 → under 100 after an edit; std_heavy 42 → about 15 | high | needs ids stable across runs; a design first (0.26) |
| 14 | compiler arenas for the middle and back ends (per-task arenas reset after each function) | −3 to −5% -O1/-O2 CPU (malloc and free are about 3%, plus realloc copies) | medium | the 0.18 plan. Little for -O0 or `check`, which are not malloc-bound |
| 15 | cheaper own and effects summaries | at most −19 (13 + 6) | low to medium | small next to the rest |
| 16 | faster hash maps and interning | under −10 | low | not hot: `intern` 1%, `HMap` 1% |
| 17 | `--time-passes` and `VOLE_PHASE_TIMES` counting module loading (today its 100 ms is in neither) | measurement | none | `main.vl`, `base/timer.vl`, `tools/query/command_line.vl` |

## 6. Recommended 0.25 scope

About one day of agent work. Every task runs on its own branch from main,
and no two tasks share a file.

| task | files (owned) | saving (wall, self-compile) | verify |
|---|---|---|---|
| **P1 resolve scans** (#1, #17) | `front/modules/lookup.vl`, `front/modules/mod.vl` (`child_module`), `base/timer.vl`, the timing calls around `load_modules` in `main.vl` and `tools/query/command_line.vl` | −65 at -O0/-O1/-O2; `check` 296 → about 230 | same-output (all levels); the compile-cost gate (`check` must fall); "imported twice" diagnostics unchanged (tests/run errors) |
| **P2 positions** (#2) | `base/diag.vl`, `front/check/mod.vl` (`check_unchecked`), `front/closures/` (`file_lines`), `front/contracts/sites.vl` | cold query and LSP 705 → about 400; −5 to −10 at -O0 | tests/query and tests/lsp byte-identical; every diagnostic's position unchanged (`tests/run.sh err`); `VOLE_LSP_TIME` |
| **P3 data as bytes** (#3) | `gen0/target.vl` (data), `back/objfile/mod.vl` (`write_object`, `gen_data`'s consumer) | −40 at -O0; −25 to −35 at -O1/-O2 | objects byte-identical before and after (same-output on the corpus, -O0/1/2, 4 targets); `-S` output unchanged; tests/threads.sh (-j1 = -j8) |
| **P4 lexer** (#4, sizing from #9) | `front/lexer/mod.vl`, `front/lexer/strings.vl` | −35; `check` −30 | `--tokens` identical over compiler/src, std and tests; same-output; the fuzzers' lexer rows |
| **P5 arch loading** (#5) | `arch/virtual.vl`, `arch/table.vl`, `arch/tables.vl` | −12 self; std_heavy −5 (−12%) | same-output; tests/run arch*; the compile-cost gate (std row) |
| **P6 assembler** (#6) | `back/objfile/assemble.vl`, `back/enc_arm64/*`, `back/objfile/resolve.vl` | −40 to −59 at -O0 -j8; −30 at -O1 | objects byte-identical (same-output); tests/objcheck; byte identity across -j and with the code cache (tests/threads.sh, tests/incremental.sh) |
| **P7 link** (#7, and #8 as a stretch) | `back/objfile/output.vl`, `back/objfile/link_macho.vl` (new), `back/objfile/macho.vl` read-only | −6 now; −28 with the in-house linker | the whole suite linked both ways; the linked binaries run the same; the self-compile's binary passes the fixpoint; `codesign -v` |

**Expected 0.25 result** (-O0 -j8):

| run | v0.24.0 | after 0.25 |
|---|---|---|
| self-compile, -c | 474 ms | about 250 to 280 ms |
| self-compile, linked | 507 ms | about 280 to 310 ms, or about 255 with P7's linker |
| `check` | 296 ms | about 190 ms |
| cold `query` and the LSP's first request | 705 ms | about 330 ms |
| -O1 | 567 ms | about 450 ms |
| -O2 | 1004 ms | about 890 ms |

**Merge order.** The tasks are independent, so merge them in any order.
P1 first is cheapest, since every other measurement then stops including
its 64 ms. Merge P3 before P6 if both change how `write_object` assembles
the data: P3 owns `back/objfile/mod.vl`, and P6 must not touch it.

**Gate.** `bootstrap/gate.sh --quick` on each task:
- `compile-cost`: the check row must not regress, and should fall.
- `threads`: byte identity across -j.
- `incremental`: byte identity with the cache.

Then on the merged release:
- `same-output` against v0.24.0: identical objects at -O0, -O1 and -O2.
  No task changes generated code.
- A new row in docs/optimizer.md with this document's baseline table,
  re-measured on an idle machine.

**0.26 (proposed): the parallel and incremental front end.**
- Lexing and parsing per file in parallel (#11).
- A design for checking in parallel (#12) and for the incremental front
  end with std's checked form cached (#13).
- Direct binary emission (#10).
- The in-house linker as the default, if P7's stretch did not land.

That is the path to a self-compile under 150 ms, and then to 100 ms.

## 7. Achieved: release-0.25

**What was merged into release-0.25.** All seven planned tasks landed, plus two fixes.

| branch | task | head |
|---|---|---|
| p25-resolve | P1 | ed63899f |
| p25-lines | P2 | 1062aa04 |
| p25-lex | P4 and P5 | 90aec0bd |
| p25-asm | P3 and P6, and faster `buf_uint`/`buf_str` | 607bb348 |
| p25-link | P7: `ld` without `sh` and `cc`, `#[link(...)]` and `-framework`, and the compiler's own Mach-O linker, the default on aarch64-macos | d0586fc4 |
| p25-det | fix: SLP's nondeterministic output at -O2 | ea990532 |
| p25-atomics | fix: litmus tests' waits yield (test only) | 66cf06b3 |

Each merge was clean and bootstrapped to a fixpoint. The suite passes:
1881 tests, 6 xfail.

**The gate.** `bootstrap/gate.sh --quick --no-x86` passes in 5:19:
- suite-O2: 1881 passed;
- threads: 2791 of 2791 compilations the same at -j1 and -j8;
- incremental: 160 of 160 series, 92% hits;
- objcheck, fuzz, abi and voltty-fuzz: pass;
- compile-cost:

  | row | instructions | against v0.24.0 |
  |---|---|---|
  | hello | 78.4 M | 0.83x |
  | std | 1012.8 M | 0.87x |
  | check | 3168 M | **0.54x** |

`tests/run.sh litmus` passed 5 times in a row, and litmus_sb_llsc did not
fail in the gate either.

**The same output.** `same-output` against v0.24.0 covers 10692
compilations. 1407 differ, and every difference is intended:
- **1221: the `try:` lines.** The diagnostics' `try:` lines name the
  compiler by the path it was run from. Rewritten to the same path, they
  are the same.
- **12: arch_own_module.vl.** A program's own `arch` module no longer
  loads std::arch, so the run-time table of files has 5 entries fewer
  (P5).
- **174: programs that use std's window, objc and gpu modules.** p25-link
  edits those std files (`#[link]`), so their panic positions, the C
  library names in their string data, and the string numbers after them
  move. Each such program differs at every level and on every target, so
  no difference is specific to one optimization level.

Nothing else differs. An -O2 difference seen once, before p25-det was
merged, did not come back in the second run.

**Measurements.** The machine was idle-ish: load 6 to 30 from other
agents (one Linux VM). Old and new runs were interleaved, best of 7.
Instructions are the fewest of the 7 and are what to trust; wall times
are the best runs. Each compiler compiles its own source, except in the
"same input" rows.

| run | v0.24.0 | release-0.25 | instructions | 0.25 plan |
|---|---|---|---|---|
| self -O0 -j8, -c | 481 ms | **281 ms** | 11.36 → 5.81 G (−48.9%) | 250–280 |
| self -O0 -j8, linked | 520 ms | **289 ms** | 11.37 → 5.96 G (−47.6%) | 255 with P7's linker |
| self -O0 -j1, linked | 581 ms | 342 ms | 11.33 → 5.93 G (−47.6%) | |
| self -O1 -j8, -c | 568 ms | 440 ms | 18.27 → 14.18 G (−22.4%) | about 450 |
| self -O1 -j8, linked | 603 ms | 448 ms | 18.25 → 14.27 G (−21.8%) | |
| self -O1 -j1, linked | 1167 ms | 978 ms | 18.19 → 14.02 G (−22.9%) | |
| self -O2 -j8, -c | 1006 ms | 891 ms | 44.74 → 41.72 G (−6.7%) | about 890 |
| self -O2 -j8, linked | 1048 ms | 896 ms | 44.74 → 41.83 G (−6.5%) | |
| self -O2 -j1, linked | 2846 ms | 2747 ms | 44.61 → 41.70 G (−6.5%) | |
| `check` | 295 ms | **207 ms** | 5.58 → 3.10 G (−44.4%) | about 190 |
| `query refs`, no cache | 705 ms | **303 ms** | 18.32 → 4.55 G (−75.1%) | about 330 |
| LSP: didOpen to the first answer (the worker's load) | 745 (657) ms | **341 (254) ms** | | about 330 |
| one-function rebuild, -O1, code cache | 563 ms | 390 ms | 10.12 → 6.25 G (−38.2%) | |
| one-function rebuild, -O2, code cache | 732 ms | 554 ms | 13.70 → 9.65 G (−29.6%) | |
| hello world, linked | 32.9 ms | **7.8 ms** | 0.10 → 0.08 G | 27, or about 13 with P7's linker |
| hello world, -c | 7.7 ms | 7.2 ms | 0.10 → 0.08 G (−17.7%) | |
| std_heavy -O0, -c | 42.3 ms | 36.6 ms | 1.15 → 1.01 G (−12.5%) | |
| std_heavy -O2, linked | 67.9 ms | **37.0 ms** | 1.15 → 1.01 G (−12.2%) | |

The same input, release-0.25's compiler/src, for both compilers:

| run | v0.24.0 | release-0.25 | instructions |
|---|---|---|---|
| self -O0 -j8, -c | 506 ms | 276 ms | 11.70 → 5.81 G (−50.3%) |
| self -O0 -j8, linked | 532 ms | 280 ms | 11.69 → 5.95 G (−49.1%) |
| self -O1 -j8, linked | 631 ms | 443 ms | 18.67 → 14.27 G (−23.6%) |
| self -O2 -j8, linked | 1089 ms | 895 ms | 46.66 → 41.84 G (−10.3%) |
| `check` (a copy without compiler/std) | 316 ms | 205 ms | 5.81 → 3.07 G (−47.1%) |

`volec examples/voltty/app/main.vl -o voltty` now builds with no extra
arguments, through the internal linker, in 0.40 s. The binary is signed
(`codesign -v`), links AppKit, QuartzCore, CoreGraphics, CoreFoundation,
Foundation, CoreText, libobjc and libSystem, and `./voltty -- true` exits
0 on its own.

**Peak RSS.** The source grew with link_macho.vl, and the syntax tree's
table (`NODES`, 18 words a node) crossed a doubling: its realloc went
from 128 to 256 MB, made in the checker. Peak RSS went up as a result:

| run | v0.24.0 source | release-0.25 source |
|---|---|---|
| -O0 | 430 MB | 539–564 MB |
| `check` | 310 MB | 445 MB |

v0.24.0 compiling the same input peaks at 570 MB too, so the cause is
the input, not the changes. #9 (tables sized up front, a smaller `Node`)
is the fix, for 0.26.

**Against the plan.** In instructions:
- -O0 fell 49%, `check` 44% and the cold query 75%.

In wall time:
- **-O0 -c** (281 ms), **-O1** (440) and **-O2** (891) are where the
  plan expected them.
- **The cold query and the LSP** (303 and 341 ms) beat the plan.
- **`check`**, at 207 ms, is 17 ms above the plan.
- **The linked self-compile**, at 289 ms, is 34 ms above the plan's
  255. The link itself now costs about 8 ms, against 33 before.
- **A hello world is 4.2 times faster linked:** 33 → 7.8 ms, of which the
  link is now about 0.6 ms.

Where the rest goes (-O0 -j1, `VOLE_PHASE_TIMES`, measured under load):

| phase | ms |
|---|---|
| read, lex and modules | 58 |
| parse and check | 166 |
| code generation, assembly, data and output | 154 |

So §4's bound is unchanged: the serial front end, now about 225 ms
including loading, is still twice the whole 100 ms budget. The next
steps are §6's 0.26 items:
- the parallel lexer and parser;
- a design for checking in parallel and for the incremental front end;
- direct binary emission;
- #9, for memory.
