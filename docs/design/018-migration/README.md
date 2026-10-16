# 0.18: the compiler's migration, as scripts

The compiler's move to values, arenas and contexts
([../contracts-verification.md](../contracts-verification.md) §4, tasks T6
and T7) is written here as `tachyonc refactor --script` files, one per step,
not merged as text: each is replayed on the integrated tree after the
feature tasks (T1–T5) have merged, and proven by `tachyonc same-output`
against the phase 0 compiler.

- `front-NN-WHAT.txt` (T6): front, tools, base, guide, main.tach.
- `middle-NN-WHAT.txt` (T7): middle, back, gen0.

Each file starts with a comment: what the step does, the compiler it was
proven against, and the instructions retired before and after on the
self-compile.
