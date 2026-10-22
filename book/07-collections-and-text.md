# 7. Collections and text

Most programs spend their time on lists of things, tables of things,
and text. This chapter covers the containers you'll use every day:
`Vec`, a list that grows; `HashMap` and `HashSet`, for looking things up;
and `BTreeMap`, when order matters. Then text: `str` and `String`, bytes,
and f-strings in full.

By the end of the chapter you'll have written a word counter: it reads
text, counts every word in it, and prints the most common ones as a
table. Chapter 11 splits it into modules, chapter 17 works on it with
the compiler's tools, and chapter 18 grows it into a real command-line
tool.

## Vec: a list that grows

A `Vec` holds any number of values of one type, one after the other.
Start a new file, `scores.vl`:

```vole scores.vl
fn main(gpa: Gpa) {
    var scores: Vec<i64> = Vec::new_in(gpa);
    scores.push(72);
    scores.push(95);
    scores.push(88);
    println(f"{scores.len()} scores, the first is {scores[0]}");
    println(f"{scores:?}");
}
```

```out
3 scores, the first is 72
[72, 95, 88]
```

`Vec<i64>` is "a Vec of `i64`s"; the type in angle brackets says what
it holds. `Vec::new_in(gpa)` makes an empty one. A Vec needs memory
that can grow, so it takes the allocator, as `String::new_in` did in
chapter 2. The Vec remembers it, so `push` doesn't need it again.
[Chapter 8](08-allocation.md) is about allocators.

`push` adds a value at the end, `len()` says how many there are, and
`scores[0]` is the first one: indexes start at 0. `{scores:?}`
prints the whole Vec. The `:?` asks for the *Debug* form, meant for
programmers rather than users; you'll see more of it at the end of the
chapter.

### Taking values out

`pop` takes the last value off. The Vec may be empty, so `pop` returns
an `Option`: `Some(value)`, or `None` when there was nothing to take.
`while let` (chapter 5) runs until it gets a `None`:

```vole
fn main(gpa: Gpa) {
    var stack: Vec<str> = Vec::new_in(gpa);
    stack.push("first");
    stack.push("second");
    stack.push("third");
    println(f"{stack.last():?}");
    while let Some(top) = stack.pop() {
        println(top);
    }
    println(f"{stack.pop():?} {stack.is_empty()}");
}
```

```out
Some("third")
third
second
first
None true
```

`last()` and `first()` look at an end without taking anything, and
also return an `Option`.

### Indexes are checked

What happens if you ask for an element that isn't there?

```vole
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    println(f"{v[3]}");
}
```

```out exit=101
main.vl:4:16: index out of bounds: index 3, length 1
```

Every index is checked when the program runs. A bad one is a panic:
the program stops with the position, the index and the length, and
exits with status 101. It never reads memory past the end of the Vec.

### Looping, and changing elements

`for x in v` visits each element in order. To change the elements, loop
over the indexes, and assign through `v[i]`:

```vole
fn main(gpa: Gpa) {
    var prices: Vec<i64> = Vec::new_in(gpa);
    prices.push(10);
    prices.push(25);
    prices.push(40);
    for i in 0..prices.len() {
        prices[i] *= 2;
    }
    var total = 0;
    for p in prices {
        total += p;
    }
    println(f"{prices:?} total {total}");
}
```

```out
[20, 50, 80] total 150
```

Inside `for p in prices`, `p` is each element in turn, read-only. Vole
has no loop yet that changes a Vec's elements in place as it goes over
them; the index loop is how you do it.

### Sorting and searching

```vole
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    for x in [31, 4, 15, 9, 26] {
        v.push(x);
    }
    v.sort();
    println(f"{v:?} {v.contains(9)} {v.contains(10)}");
    v.retain(|x| x % 2 == 1);
    println(f"{v:?}");

    var fruit: Vec<str> = Vec::new_in(gpa);
    fruit.push("pear");
    fruit.push("fig");
    fruit.push("banana");
    fruit.sort_by_key(|s| s.len());
    println(f"{fruit:?}");
}
```

```out
[4, 9, 15, 26, 31] true false
[9, 15, 31]
["fig", "pear", "banana"]
```

`sort()` puts the elements in increasing order, and `contains` says
whether a value is there. `retain` keeps only the elements for which a
test is true, and `sort_by_key` sorts by something computed from each
element: here, the length of each word.

`|x| x % 2 == 1` is a *closure*, a small function written right where
it's used: it takes `x` and returns whether `x` is odd. Chapter 10 is
about closures; for now, read `|x|` as "given x".

### Pushing while looping

Here's a mistake that is easy to make. Let's double a list by pushing a
copy of each element while we loop over it:

```vole
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    for x in v {
        v.push(x);
    }
    println(f"{v:?}");
}
```

```err
error[own.conflict]: 'v.push(x)' may change the elements of 'v' while the 'for' at main.vl: line 5, column 5 iterates over them
 --> main.vl: line 6, column 9
  = help: loop over the indexes (the loop sees the elements present when it starts), or collect the new elements and append them after the loop | try: volec edit patch main --old 'for x in v {' --new 'for i in 0..v.len() { let x = v[i];'
```

Pushing can move a Vec's elements to a bigger block of memory, and the
loop is still walking the old one. In many languages this is a bug you
find at run time, if you're lucky. In vole it doesn't compile. The
`try:` line shows the fix: loop over the indexes instead. `0..v.len()`
is worked out once, when the loop starts, so the loop sees the two
elements that were there and stops:

```vole
fn main(gpa: Gpa) {
    var v: Vec<i64> = Vec::new_in(gpa);
    v.push(1);
    v.push(2);
    for i in 0..v.len() {
        let x = v[i];
        v.push(x);
    }
    println(f"{v:?}");
}
```

```out
[1, 2, 1, 2]
```

### Passing a Vec to a function

A Vec is an owned value, so the conventions from
[chapter 4](04-value-semantics.md) apply: a function reads it, changes
it, or takes it, and its signature says which.

```vole
fn total(v: Vec<i64>) -> i64 {
    var t = 0;
    for x in v {
        t += x;
    }
    t
}

fn add_bonus(v: inout Vec<i64>, bonus: i64) {
    for i in 0..v.len() {
        v[i] += bonus;
    }
}

fn main(gpa: Gpa) {
    var points: Vec<i64> = Vec::new_in(gpa);
    points.push(3);
    points.push(4);
    add_bonus(&points, 10);
    println(f"{points:?} {total(points)}");
}
```

```out
[13, 14] 27
```

`total` reads (no copy is made), `add_bonus` changes the caller's Vec
(so the call says `&points`), and a `sink` parameter would take it.

## Arrays, Vecs and slices

Vole has three kinds of lists, and they work together:

- An *array*, `[i64; 3]`, has a length fixed in its type. It's a plain
  value: `let b = a;` copies it.
- A `Vec<i64>` can grow, and its elements live in memory from an
  allocator.
- A *slice*, `[i64]`, is a view of elements that something else owns:
  an array, a Vec, or a part of either.

A function that only reads a list should take a slice. Then it works on
all three:

```vole
fn largest(xs: [i64]) -> i64 {
    var best = xs[0];
    for x in xs {
        if x > best {
            best = x;
        }
    }
    best
}

fn main(gpa: Gpa) {
    let days: [i64; 4] = [12, 19, 7, 15];
    var temps: Vec<i64> = Vec::new_in(gpa);
    temps.push(3);
    temps.push(-2);
    println(largest(days));
    println(largest(temps));
    println(largest(days[2..4]));
}
```

```out
19
3
15
```

`days[2..4]` is the slice of elements 2 and 3: the start is included,
the end is not. Making a slice copies nothing, and the compiler checks
that it isn't used after what it views changes, as chapter 4 showed.

## Text: str and String

Text in vole is UTF-8, and comes in two types, like lists do:

- `str` is a view of text that something else owns. A string literal
  is a `str`, and so is every piece cut out of other text.
- `String` owns its text, and can grow. Its memory comes from an
  allocator.

### A literal is a str where a str goes

There is one surprise to know about first. Try this:

```vole
fn main() {
    let line = "  hello  ";
    println(line.trim());
}
```

```err
error[type error]: no method 'trim' on type '[u8]'
 --> main.vl: line 3, column 13
  = help: `[u8]` is bytes; text is `str` (UTF-8), which has it: a literal is a `str` where one goes (`let s: str = "..";`, `fn f(s: &str)`); bytes become one by `str::from_utf8(b)?`
  = try: trim(line)
  = try: volec fix --suggested main.vl
```

A string literal can be text (`str`) or plain bytes (`[u8]`), and it's
a `str` only where the code asks for one. With nothing to say which,
`line` is bytes, which have no `trim` method. The fix is to say what
`line` is:

```vole
fn main() {
    let line: str = "  hello  ";
    println(f"[{line.trim()}]");
}
```

```out
[hello]
```

A literal passed to a function that takes a `str`, or used as the
receiver of a `str` method (`"a,b".split(',')`), is a `str` without
help. It's the `let` with no type that needs one.

### Taking text apart

`str` has the methods you'd expect, with the names Rust uses. Here
are the most common:

```vole
fn main() {
    let line: str = "  width = 80  ";
    let (key, value) = line.split_once('=').unwrap();
    let n = value.trim().parse::<i64>().unwrap();
    println(f"[{key.trim()}] is {n}");
    println(f"{line.find("80"):?} {line.contains("width")}");
    println(f"{line.trim().starts_with("width")} {line.trim().strip_prefix("width"):?}");
    for part in "a,b,,c".split(',') {
        print(f"[{part}]");
    }
    println("");
    for word in "the quick\n  brown fox".split_whitespace() {
        print(f"<{word}>");
    }
    println("");
}
```

```out
[width] is 80
Some(10) true
true Some(" = 80")
[a][b][][c]
<the><quick><brown><fox>
```

- `trim()` removes the whitespace at both ends.
- `split_once(p)` cuts at the first `p`, giving the two sides, or
  `None` if there is no `p`.
- `parse::<i64>()` reads a number, as in chapter 2.
- `find(p)` gives the byte index where `p` starts, or `None`; `contains`,
  `starts_with` and `strip_prefix` do what their names say.
- `split(p)` gives the pieces between each `p`, empty ones too;
  `split_whitespace()` gives the words, however much space is between
  them; `lines()` gives the lines.

A *pattern* `p` can be a `str` (`"80"`) or a single byte (`'='`).

Every one of these returns views of the original text: `key`, `value`
and each `part` point into `line`. Nothing was copied, and none of them
needed an allocator.

### Building text: String

When you need new text, make a `String`:

```vole
fn main(gpa: Gpa) {
    var s = String::new_in(gpa);
    s.push_str("vole");
    s.push_str(" is ");
    s.push_fmt(f"{2 + 2} letters");
    println(s);

    let name = String::from_in("Ada", gpa);
    println(f"{name} has {name.len()} letters");
}
```

```out
vole is 4 letters
Ada has 3 letters
```

`String::new_in(gpa)` makes an empty one, and `String::from_in("...",
gpa)` one with some text already in it. `push_str` appends text, and
`push_fmt` appends an f-string. A `String` has every method a `str` has
(`name.len()`, `name.trim()`).

A function that only reads text takes a `str`, and you can give it a
`String` or a literal:

```vole
fn shout(s: str, gpa: Gpa) -> String {
    s.to_uppercase_in(gpa)
}

fn main(gpa: Gpa) {
    let name = String::from_in("ada", gpa);
    println(shout(name, gpa));
    println(shout("lovelace", gpa));
}
```

```out
ADA
LOVELACE
```

### Methods that make new text take an allocator

`to_uppercase_in` makes a new `String`, so it needs memory, so it takes
the allocator. The methods that build text all work this way: their
names end in `_in` and the allocator is their last argument.
`to_lowercase_in`, `replace_in(from, to, gpa)` and `repeat_in(n, gpa)`
are the ones you'll use most. If you reach for the name without `_in`,
the compiler tells you:

```vole
fn main(gpa: Gpa) {
    let name: str = "vole";
    let loud = name.to_uppercase();
    println(loud);
}
```

```err
error[type error]: allocation is explicit: pass an allocator (try: to_uppercase_in(gpa))
 --> main.vl: line 3, column 16
  = help: this function's `gpa` is the allocator to pass
  = try: volec fix --only alloc016 main.vl
  = try: volec fix --suggested main.vl
```

That `_in` is the whole rule, and it's how you can tell, reading a
line of code, that it allocates.

If a function insists on a `String` and you give it a literal, you get
a type error with the conversion in its `try:` line. Here a map's keys
are `String`s, so looking one up needs a `String` too:

```vole
fn main(gpa: Gpa) {
    var ages: HashMap<String, i64> = HashMap::new_in(gpa);
    ages.insert(String::from_in("ada", gpa), 36);
    println(f"{ages.get("ada"):?}");
}
```

```err
error[type error]: expected 'String', got '[u8]'
 --> main.vl: line 4, column 25
  = help: a String owns its text, on an allocator: `String::from_in(s, gpa)`; a `str` is a view of one (`&str` parameters take both)
  = try: String::from_in("ada", gpa)
```

You'll meet `HashMap` properly in a moment.

> **If you know Rust:** the methods have Rust's names, but anything
> that allocates takes an allocator and ends in `_in`:
> `to_uppercase_in(gpa)`, `to_string_in(gpa)`, `collect_in(gpa)`. A
> `str` parameter is Rust's `&str`, without the `&`.

### Characters and bytes

UTF-8 uses one byte for each ASCII character and two to four for
others. `len()` counts bytes; `chars()` goes through the *code points*,
the numbers Unicode gives each character:

```vole
fn main(gpa: Gpa) {
    let word: str = "café";
    println(f"{word.len()} bytes, {word.chars().count()} code points");
    for c in word.chars() {
        print(f"{c} ");
    }
    println("");
    var s = String::new_in(gpa);
    s.push(0x263A);
    println(f"{s} is {s.len()} bytes");
    let b = 'c';
    println(f"{b} {b:c} {word[0] == b}");
}
```

```out
5 bytes, 4 code points
99 97 102 233 
☺ is 3 bytes
99 c true
```

Vole has no `char` type yet. A code point is a `u32`, so printing one
prints a number, and `s.push(0x263A)` adds one to a `String`. A
character in single quotes, `'c'`, is a byte (`u8`), and `{b:c}` prints
a byte as the character it stands for. `word[0]` is the first byte of
the text.

## Bytes: [u8] and Buf

Not all data is text. A file might be an image, and a network packet
is just bytes. For those, vole has `[u8]`, a slice of bytes, and `Buf`,
a growable buffer of them, the bytes' `String`:

```vole
fn show(bytes: [u8]) {
    match str::from_utf8(bytes) {
        Ok(text) => println(f"text: {text}"),
        Err(e) => println(f"not text: {e}"),
    }
}

fn main(gpa: Gpa) {
    var b = Buf::new_in(gpa);
    b.push_str("hi");
    b.push(0x21);
    show(b.as_slice());

    var raw = Buf::new_in(gpa);
    raw.push(0xff);
    raw.push(0x41);
    show(raw.as_slice());
}
```

```out
text: hi!
not text: invalid utf-8 sequence of 1 bytes from index 0
```

`b.as_slice()` is a view of the `Buf`'s bytes. `str::from_utf8` checks
that bytes are valid UTF-8 and, if they are, gives you a `str` of the
same bytes, without copying them. Bytes that aren't UTF-8 are an `Err`.

Use `str` and `String` for text, and `[u8]` and `Buf` when the topic is
bytes. A `str` goes where a `[u8]` is wanted for free; the other way
round goes through `str::from_utf8`, because not every byte sequence is
text.

## Reading all of stdin

Now we can start the word counter. Its first job is to read everything
on standard input. Start `words.vl`:

```vole words.vl
fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = str::from_utf8(input.as_slice()).unwrap();
    var words = 0;
    for word in text.split_whitespace() {
        words += 1;
    }
    println(f"{text.lines().count()} lines, {words} words, {text.len()} bytes");
}
```

```in
The cat and the dog.
The END, the end!
```

```out
2 lines, 9 words, 39 bytes
```

`read_stdin_in(gpa)` reads all of standard input into a `Buf`, and
returns a `Result` because reading can fail. `str::from_utf8` turns
the bytes into text, and from there it's all `str` methods.
`lines()` gives the lines one at a time, and `count()` counts them.
Chapter 10 is about this kind of value, an *iterator*, and the many
things you can do with one.

Reading everything at once is the simplest way when the input fits in
memory. For input too big for that, chapter 2's `BufReader` reads a
line at a time, and `BufReader::lines_in(gpa)` gives the lines one by
one. For input that is mostly numbers separated by spaces, `Scanner`
reads one token at a time (`volec guide std#input`).

## HashMap: looking things up

A `HashMap` stores *values* under *keys*, and finds a value from its
key quickly, however many there are:

```vole
fn main(gpa: Gpa) {
    var ages: HashMap<str, i64> = HashMap::new_in(gpa);
    ages.insert("ada", 36);
    ages.insert("alan", 41);
    let old = ages.insert("ada", 37);
    println(f"{old:?} {ages.get("ada"):?} {ages.get("bob"):?}");
    println(f"{ages.contains_key("alan")} {ages.len()}");
    println(f"{ages.remove("alan"):?} {ages.len()}");
}
```

```out
Some(36) Some(37) None
true 2
Some(41) 1
```

`HashMap<str, i64>` maps `str` keys to `i64` values. `insert` returns
the value the key had before, if any. `get` returns an `Option`: a copy
of the value, or `None` when the key isn't there. `remove` takes the
key out and gives back its value.

### Counting

Counting things is the most common job for a map, and it has a method
of its own:

```vole
fn main(gpa: Gpa) {
    var counts: HashMap<str, i64> = HashMap::new_in(gpa);
    for w in "a b a c a b".split(' ') {
        counts.get_or_insert(w, 0)[0] += 1;
    }
    println(f"{counts.get("a"):?} {counts.get("b"):?} {counts.get("z"):?}");
}
```

```out
Some(3) Some(2) None
```

`counts.get_or_insert(w, 0)` finds `w`'s value, putting `0` in first if
`w` isn't there yet, and lets you change it in place. The `[0]` needs
explaining: what it returns is a view of the one value inside the map,
and in vole a writable view is a slice, here a slice of length one. So
`[0]` is that value, and `+= 1` adds one to it. It's a quirk of a young
language, and you'll write this line often enough that it soon reads
naturally.

> **If you know Rust:** there is no `entry` API; `get_or_insert(k,
> d)[0]` is `*map.entry(k).or_insert(d)`, and `get_mut(k)` gives the
> same one-element slice in an `Option`.

### The order of a HashMap

You can loop over a map's pairs, but in no particular order:

```vole skip
    for (word, n) in counts.iter() {
        println(f"{word} {n}");
    }
```

The order depends on the keys' hashes, and can change when the map
grows. When order matters, sort the pairs, as the word counter will
do, or use a `BTreeMap`.

### Your own types as keys

A key needs two things: a way to compare keys for equality, and a
hash. Numbers, `str`, `String` and tuples of them have both. For your
own struct, add `#[derive(Eq, Hash)]` above it; chapter 9 explains what
that writes.

### HashSet, BTreeMap and heaps

A `HashSet` is a map with keys and no values, for asking "have I seen
this?". A `BTreeMap` is a map that keeps its keys sorted, so looping
over it goes from the smallest key up, and `range` gives part of it:

```vole
use std::BTreeMap;
use std::HashSet;

fn main(gpa: Gpa) {
    var seen: HashSet<i64> = HashSet::new_in(gpa);
    println(f"{seen.insert(3)} {seen.insert(3)} {seen.contains(3)}");

    var grades: BTreeMap<i64, str> = BTreeMap::new_in(gpa);
    grades.insert(90, "A");
    grades.insert(70, "C");
    grades.insert(80, "B");
    for (score, grade) in grades.iter() {
        print(f"{score}:{grade} ");
    }
    println("");
    for (score, grade) in grades.range(75, 95) {
        print(f"{score}:{grade} ");
    }
    println("");
}
```

```out
true false true
70:C 80:B 90:A 
80:B 90:A 
```

`insert` on a set says whether the value was new. `range(75, 95)`
includes 75 and stops before 95, like `75..95`.

`HashSet` and `BTreeMap` aren't in the prelude, so they need a `use`
line. Two more containers are in the prelude: `BinaryHeap`, a *priority queue*, where
you push values in any order and `pop` always gives back the largest
one left, and `MinHeap`, which gives back the smallest.

## Counting the words

Back to the word counter. Each word should be counted without the
punctuation around it ("dog." is "dog") and without caring about case
("The" is "the"). Here is `words.vl` again, counting:

```vole words.vl
// Letters, digits and apostrophes are parts of words. So is every
// byte of a non-ASCII character (0x80 and up), so "café" stays whole.
fn is_word_byte(b: u8) -> bool {
    match b {
        'a'..='z' | 'A'..='Z' | '0'..='9' | '\'' => true,
        0x80..=0xff => true,
        _ => false,
    }
}

// The word without the punctuation around it: "end!" is "end".
fn trim_punct(word: str) -> str {
    var start = 0;
    var end = word.len();
    while start < end && !is_word_byte(word[start]) {
        start += 1;
    }
    while end > start && !is_word_byte(word[end - 1]) {
        end -= 1;
    }
    word[start..end]
}

fn count_words(text: str, gpa: Gpa) -> HashMap<String, i64> {
    var counts: HashMap<String, i64> = HashMap::new_in(gpa);
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        counts.get_or_insert(w.to_lowercase_in(gpa), 0)[0] += 1;
    }
    counts
}

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = str::from_utf8(input.as_slice()).unwrap();
    let counts = count_words(text, gpa);
    let the = String::from_in("the", gpa);
    println(f"{counts.len()} different words, 'the' {counts.get(the):?} times");
}
```

```in
The cat and the dog.
The END, the end!
```

```out
5 different words, 'the' Some(4) times
```

`trim_punct` moves two indexes inwards past the bytes that aren't part
of a word, then returns the slice between them: a view of the word,
with nothing copied. `word[start]` is one byte of the text.

`count_words` lowercases each word with `to_lowercase_in(gpa)`, which
makes a new `String`, and that `String` becomes the key. That's why
the map is `HashMap<String, i64>` and not `HashMap<str, i64>`: a
lowercased word is new text, not a view of the input. The map takes
the `String`, and drops it with the map at the end of the program.

## Formatting with f-strings

The last step is printing a table, so let's look at f-strings in full.
After the expression in a hole, a colon starts a *format spec*:

```vole
fn main() {
    let n = 42;
    let pi = 3.14159;
    let word: str = "vole";
    println(f"[{n:>6}] [{n:<6}] [{n:06}]");
    println(f"[{n:x}] [{n:X}] [{n:b}]");
    println(f"[{pi:.2}] [{pi:8.3}]");
    println(f"[{word:>8}] [{word:<8}] [{word:?}]");
    println(f"{{n}} is {n}, and twice that is {n * 2}");
}
```

```out
[    42] [42    ] [000042]
[2a] [2A] [101010]
[3.14] [   3.142]
[    vole] [vole    ] ["vole"]
{n} is 42, and twice that is 84
```

- A number is a *width*: `{n:>6}` pads to six places, on the left
  (`>`, right-aligned) or the right (`<`). Numbers go right by default,
  text left. A `0` before the width pads with zeros.
- `.2` gives a float two decimals.
- `x`, `X` and `b` print an integer in hex or binary.
- `?` is the Debug form: text in quotes, a Vec in brackets, an `Option`
  as `Some(...)`.
- `{{` and `}}` are a literal brace.

Widths count bytes for now, not characters, so a column with non-ASCII
text in it won't line up exactly.

Every type you can print has a *Display* form (the plain `{x}`) or a
Debug form (`{x:?}`), or both. Numbers and text have both; a `Vec` or an
`Option` has only Debug, because there's no single obvious way to show
one to a user. For your own types, `#[derive(Debug)]` writes the Debug
form for you (chapter 5), and chapter 9 shows how to write a Display
form.

An f-string can also become text you keep, instead of being printed:

```vole
fn main(gpa: Gpa) {
    let label = to_string_in(f"{3}-{"vole"}", gpa);
    println(f"{label} has {label.len()} bytes");
    var report = String::new_in(gpa);
    for i in 1..4 {
        report.push_fmt(f"{i * i} ");
    }
    println(report.trim());
}
```

```out
3-vole has 6 bytes
1 4 9
```

`to_string_in(f"...", gpa)` makes a `String`; `push_fmt` appends to one
you have. (`format_in(f"...", gpa)` does the same into a `Buf`.)

## The word counter

Now let's finish the program. To print the most common words, we take
the pairs out of the map into a `Vec`, sort it, and print the first
five rows. Here is the complete `words.vl`:

```vole words.vl
// Count the words on stdin, and print the most common ones.

// Letters, digits and apostrophes are parts of words. So is every
// byte of a non-ASCII character (0x80 and up), so "café" stays whole.
fn is_word_byte(b: u8) -> bool {
    match b {
        'a'..='z' | 'A'..='Z' | '0'..='9' | '\'' => true,
        0x80..=0xff => true,
        _ => false,
    }
}

// The word without the punctuation around it: "end!" is "end".
fn trim_punct(word: str) -> str {
    var start = 0;
    var end = word.len();
    while start < end && !is_word_byte(word[start]) {
        start += 1;
    }
    while end > start && !is_word_byte(word[end - 1]) {
        end -= 1;
    }
    word[start..end]
}

fn count_words(text: str, gpa: Gpa) -> HashMap<String, i64> {
    var counts: HashMap<String, i64> = HashMap::new_in(gpa);
    for word in text.split_whitespace() {
        let w = trim_punct(word);
        if w.is_empty() {
            continue;
        }
        counts.get_or_insert(w.to_lowercase_in(gpa), 0)[0] += 1;
    }
    counts
}

// The pairs, most common first; words with the same count in
// alphabetical order.
fn sorted_counts(counts: HashMap<String, i64>, gpa: Gpa) -> Vec<(String, i64)> {
    var rows: Vec<(String, i64)> = Vec::new_in(gpa);
    for (word, n) in counts.iter() {
        rows.push((word.clone(), n));
    }
    rows.sort_by(|a, b| if a.1 != b.1 { b.1 - a.1 } else { a.0.cmp(b.0) });
    rows
}

fn print_table(rows: [(String, i64)], top: i64) {
    let shown = if rows.len() < top { rows.len() } else { top };
    println(f"{"word":<12} {"count":>5}");
    println(f"{"----":<12} {"-----":>5}");
    for (word, n) in rows[0..shown] {
        println(f"{word:<12} {n:>5}");
    }
}

fn main(gpa: Gpa) {
    let input = read_stdin_in(gpa).unwrap();
    let text = str::from_utf8(input.as_slice()).unwrap();
    let counts = count_words(text, gpa);
    let rows = sorted_counts(counts, gpa);
    print_table(rows, 5);
    println(f"{counts.len()} different words");
}
```

```in
The cat and the dog. The END, the end!
A cat? A dog, a bird; a cat.
It's the end.
```

```out
word         count
----         -----
the              5
a                4
cat              3
end              3
dog              2
8 different words
```

Let's look at the two new functions.

`sorted_counts` copies each pair into a `Vec<(String, i64)>`, a Vec of
tuples. `word.clone()` is needed because the map keeps its own keys:
`counts` is only read here, so its `String`s stay in it, and the Vec
gets copies.

Then `sort_by` sorts the rows with a comparison we give it: a closure
that takes two rows, `a` and `b`, and returns a negative number if `a`
goes first, a positive one if `b` does, and zero if they're equal. `b.1
- a.1` puts the bigger count first. When the counts are equal,
`a.0.cmp(b.0)` compares the words, so ties come out in alphabetical
order. Without that, the order of equal counts would be the map's
order, which is no order at all.

`print_table` takes a slice of rows, so `main` passes the Vec as it is.
It works out how many rows to show, makes a slice of that many, and
loops over it. `for (word, n) in ...` takes each tuple apart as it goes.
The header uses the same widths as the rows, so the columns line up.

Try it on a bigger text, any text file you have:

```sh
volec words.vl -o words
./words < some-book.txt
```

> **If you know Python:** there are no list comprehensions or
> `Counter`. Loops like these do the job, and chapter 10's iterator
> chains (`map`, `filter`, `collect_in`) fill the role of
> comprehensions.

## Summary

- `Vec<T>` grows: `push`, `pop` (an `Option`), `len`, checked `v[i]`,
  slices `v[a..b]`, `sort`, `sort_by_key`, `sort_by`, `retain`,
  `contains`. Change elements through an index loop.
- Arrays have a fixed length; slices view either; functions that read a
  list take a slice.
- `HashMap` finds values by key; `get_or_insert(k, 0)[0] += 1` counts;
  its order is unspecified. `HashSet` for membership, `BTreeMap` for
  sorted keys, `BinaryHeap` and `MinHeap` as priority queues.
- `str` is a view of UTF-8 text and `String` owns some; a literal is a
  `str` where a `str` goes. View methods (`trim`, `split`, `lines`) copy
  nothing; methods that make text take an allocator and end in `_in`.
- `[u8]` and `Buf` hold bytes; `str::from_utf8` checks them into text.
- f-string specs: width and alignment, zero padding, precision, hex,
  Debug.

The word counter called `gpa` a lot. The next chapter is about where
memory comes from: why every allocation names its allocator, and the
allocators you can choose instead of `gpa`.

## Try it yourself

- Make the counter take the number of rows from the first line of
  input, as `5` or `10`, with `split_once('\n')` and `parse`.
- Print each word's share of all the words as a percentage with one
  decimal: `{p:.1}%`.
- Skip short words: change `count_words` so it ignores words of one or
  two bytes.
