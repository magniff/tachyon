# Trait purity: `Hash`, `Eq` and `Ord` are `#[pure]`

The most frequent words of a text, counted without regard to case. The
words are keys of a `HashMap`, as a type of the program, `Word`, with a
hand-written `Hash` and `Eq` that look at the lowercase bytes; the
counts are sorted by a hand-written `Ord`.

std declares the methods of these three traits `#[pure]`:

```tach
pub trait Eq { #[pure] fn eq(self, other: Self) -> bool; }
pub trait Ord { #[pure] fn cmp(self, other: Self) -> i64; }
pub trait Hash { #[pure] fn hash(self) -> u64; }
```

A declaration on a trait's method binds every impl of it, the program's
and derived ones alike: an `eq`, `cmp` or `hash` may not allocate, do
I/O or touch a static. It may panic, loop, and read what it is given.

Why: the containers and algorithms that call them decide how often. A
`HashMap` hashes a key on every insert and every lookup, and every key
again each time it grows; a sort compares as often as its algorithm
needs, in its own order. A `hash` that counted its calls in a static
would count the map's internals, and change when they do; an `eq` that
printed would print a different trace for every version of the map. And
the optimizer may compute a pure call once and reuse it.

Every command below is run by `tests/walkthrough/run.sh` in a copy of
this directory, and its output is checked against this file;
`tests/examples/effects-trait-purity.test` runs the program.

## Run it

```console
$ volec main.vl -o words && ./words
26 words, 13 different
  5 The
  4 cat
  3 a
  3 mat
  2 on
ok: built words
```

## The impls' effects

```console
$ volec query effects crate
crate::lower	none
<crate::Word as Hash>::hash	none
<crate::Word as Eq>::eq	panic
<crate::Count as Ord>::cmp	panic
crate::trim_word	panic
crate::is_letter	none
crate::main	alloc(Gpa) io global panic diverge
```

`Word::hash` is `none`. `Word::eq` and `Count::cmp` index (`panic`),
which `#[pure]` allows.

## A hash that counts its calls

Counting how often `hash` runs, in a static: one edit adds the static
and changes `hash` (`edit apply` takes several items' new text, here on
stdin):

```console
$ volec edit apply <<'EOF'
> @@ new before Word
> // How many times hash was called.
> static var HASHES: i64 = 0;
> @@ Word::hash
>     fn hash(self) -> u64 {
>         HASHES += 1;
>         var h = 0xcbf29ce484222325u64;
>         for b in self.text {
>             h = (h ^ lower(b) as u64) * 0x100000001b3u64;
>         }
>         h
>     }
> EOF
main.vl:23:5: error[effect] 'Word::hash' implements 'Hash::hash', which is #[pure], but it uses a static (global): 'HASHES' at main.vl:24:9 is a static's (global) | help: pass the state in as a parameter, or remove #[pure] (the trait's) | try: volec query effects Word::hash --why global  [edited: <crate::Word as Hash>::hash]
error edit.breaks: 1 new error; nothing written
try: volec edit apply --no-check
[exit 1]
```

The error is at the impl's `hash`, and says whose declaration it breaks:
`Hash::hash`'s, std's. (The help's two ways out are for a function of
your own; for std's traits, keep the count outside the impl: around the
calls of `insert` and `get` that you make.)

## An eq that prints

A debugging print in `eq`:

```console
$ volec edit patch Word::eq --old '        if self.text.len() != other.text.len() {' --new '        println(f"comparing {self.text} and {other.text}");
>         if self.text.len() != other.text.len() {'
main.vl:30:5: error[effect] 'Word::eq' implements 'Eq::eq', which is #[pure], but it does io: 'println(f"comparing {self.text} and {other.t..' at main.vl:31:9 calls 'std::fmt::println' | help: return the data and let the caller print it, or remove #[pure] (the trait's) | try: volec query effects Word::eq --why io  [edited: <crate::Word as Eq>::eq]
error edit.breaks: 1 new error; nothing written
try: volec edit patch Word::eq --old '        if self.text.len() != other.text.len() {' --new '        println(f"comparing {self.text} and {other.text}");
        if self.text.len() != other.text.len() {' --no-check
[exit 1]
```

## Derived impls

`#[derive(Eq, Hash, Ord)]` writes impls that compare and hash the
fields, so they are pure when the fields' impls are: every number,
`[u8]`, and every type of std is. They are checked the same way.

## Pure is not deterministic

`#[pure]` is about effects: no allocation, no I/O, no statics. It does
not make a function's result depend only on its arguments: an impl can
still read memory through a raw pointer it holds (in `unsafe` code), and
change what it answers. std's sort is tested with such comparators
(tests/run/std_sort_adversarial.vl: random, always-less, alternating):
they keep their state behind a pointer in each key, which is `unsafe`,
not `global`. An `Ord` that is not an order leaves a slice in some
order, never out of bounds.

## Read more

- `volec guide effects`, section "Declaring" (trait declarations).
- `volec guide traits`: traits, impls, derive.
- [pure-and-no-alloc](../pure-and-no-alloc/): `#[pure]` on functions.
