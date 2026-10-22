# 4. Value semantics: let, inout, sink

This is the chapter that makes vole different from the languages you
probably know, so we'll take it slowly. It answers two questions every
program has to answer somehow: when two parts of a program use the same
data, who may change it? And when is its memory given back?

By the end of the chapter you'll know what it means that every value in
vole has one owner, when a value is copied and when it is moved, and how
a function says what it does with each argument: reads it, changes it,
or takes it. You'll also see why vole has no references to manage and
no lifetimes to write, even though it has no garbage collector.

Our running example is a playlist: songs, and functions that add to a
playlist, total it up, and put it away.

## The problem

Here is a small program in Python:

```text
a = [1, 2, 3]
b = a
b.append(4)
print(a)        # [1, 2, 3, 4]
```

`b = a` didn't copy the list. It made a second name for the same list,
so a change through `b` shows up through `a`. That's convenient, and
it's also the source of a whole family of bugs: a function that changes
a list its caller still uses, two parts of a program that each think
they own some data, a loop that changes the list it's going through.
Python pays for this sharing in another way too: a garbage collector
has to work out, while the program runs, when nobody can reach a value
any more.

Other languages answer the same questions differently. C lets you share
freely and makes you call `free` yourself, at exactly the right moment,
or else. Rust lets you share through *references*, and checks with a
*borrow checker* that no reference outlives its data, which sometimes
means writing out *lifetimes* to explain to the compiler how long each
reference lives.

Vole's answer is called *mutable value semantics*. The idea is that
every value behaves like a number does. When you write

```vole
fn main() {
    let a = 5;
    var b = a;
    b += 1;
    println(f"{a} {b}");
}
```

```out
5 6
```

nobody is surprised that `a` is still 5. `b = a` gave `b` its own 5.
In vole, a list, a string, a struct, any value at all, behaves like
that: assigning it or passing it never creates a second name through
which someone else can change it, unless you hand one over on purpose,
in a way you can see at the call. You can always change what is yours
(`var`), and nothing changes behind your back. The rest of this chapter
is about how vole keeps that promise without copying everything all
the time.

## Plain and owned values

Here's our song type. Structs are chapter 5's subject; for now, a
`struct` is a value with named fields.

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn main(gpa: Gpa) {
    let first = Song { title: "Blue Moon", seconds: 185 };
    var edit = first;
    edit.seconds = 190;
    println(f"{first.seconds} {edit.seconds}");

    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(first);
    list.push(Song { title: "Summertime", seconds: 210 });
    println(f"{list.len()} songs");
}
```

```out
185 190
2 songs
```

`var edit = first;` copied the song. Changing `edit` left `first` alone,
just as with the numbers. A song is a couple of small fields, so
copying it costs about as much as copying a few numbers.

Values like that are called *plain*: numbers, `bool`, and tuples,
arrays and structs made only of plain values. `=` copies them, bit for
bit, as C would. (A `Song` holds a `str`, which is a *view* of text
stored somewhere else. Views are copied too, and the section on views,
later in this chapter, explains them. For now, read a `Song` as plain.)

`list` is different. A `Vec` (a growable list, chapter 7) holds its
elements in memory it got from an allocator, and that memory can be
large. A value that holds memory like this is *owned*: `Vec`, `String`,
`HashMap`, and any struct with one of those inside. What does `=` do
with an owned value? Let's try:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    let backup = list;
    list.push(Song { title: "Summertime", seconds: 210 });
    println(f"{backup.len()} {list.len()}");
}
```

```err
error[own.moved]: 'list' is used here after it moved at 6:18
 --> playlist.vl: line 7, column 5
  = help: use it before the move, pass a copy where it moves ('.clone()'), or let the callee borrow it: a let parameter ('x: T'), not 'sink' | try: volec edit patch playlist.vl:6 --old 'let backup = list;' --new 'let backup = list.clone();'
```

`let backup = list;` *moved* the list into `backup`. After a move, the
old name is dead: `list` no longer holds anything, and using it is an
error. The error says where the move happened (line 6, column 18) and
where the dead name was used (line 7).

Why move instead of copy? Copying a list means allocating new memory
and copying every element, which is too expensive to happen silently
on every `=`. Sharing, as Python does, would break the promise that
nothing changes behind your back. A move is cheap, because only the
list's small handle changes hands, not its elements, and it keeps the
promise: there is still exactly one name for the list, it's just a
different one.

If you really want two separate lists, say so with `.clone()`. That's
what the `try:` line at the end of the error does: it is a command
that changes line 6 to `let backup = list.clone();`.

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    let backup = list.clone();
    list.push(Song { title: "Summertime", seconds: 210 });
    println(f"{backup.len()} {list.len()}");
}
```

```out
1 2
```

Now there are two lists, and the push changed only one of them.

You never declare whether a type is plain or owned. The compiler works
it out from what the type holds: a struct of numbers is plain, and the
moment you add a `Vec` field to it, it is owned.

## Drops: giving memory back

An owned value has exactly one owner at a time, the variable that
holds it. That makes the second question, when to give the memory
back, easy: when the owner goes away. At the end of the block where a
variable was declared, its value is *dropped*, which for a `Vec` means
its memory goes back to the allocator. You never call `free`.

To watch drops happen, we can give a type some code to run when it is
dropped, with `impl Drop`:

```vole drops.vl
struct Noisy { id: i64 }

impl Drop for Noisy {
    fn drop(inout self) {
        println(f"dropping {self.id}");
    }
}

fn main() {
    let a = Noisy { id: 1 };
    let b = Noisy { id: 2 };
    {
        let c = Noisy { id: 3 };
        println(f"the inner block ends ({c.id})");
    }
    let d = Noisy { id: 4 };
    drop(d);
    println(f"main ends ({a.id} {b.id})");
}
```

```out
the inner block ends (3)
dropping 3
dropping 4
main ends (1 2)
dropping 2
dropping 1
```

A type with a `Drop` is owned, like a `Vec`, even though it holds only
a number. Reading the output from the top:

- `c` is dropped when the inner block ends, right after its last line.
- `drop(d)` drops `d` early, on the spot. After it, `d` is dead, as if
  it had moved (it did: into `drop`).
- `a` and `b` are dropped when `main` ends, the last declared first.

Drops happen on every way out of a block: falling off the end,
`return`, `break`, `continue`. A value that was moved somewhere else
isn't dropped where it was; its new owner drops it later. So every
owned value is dropped exactly once, and you never free memory twice or
forget to free it.

You'll rarely write `impl Drop` yourself. A struct without one is
dropped field by field, so a struct holding a `Vec` frees the `Vec`'s
memory with no code from you.

## let: reading

Now let's write functions that work on a playlist. The first one only
reads it:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn total_seconds(list: Vec<Song>) -> i64 {
    var total = 0;
    for s in list {
        total += s.seconds;
    }
    total
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    list.push(Song { title: "Summertime", seconds: 210 });
    println(f"{total_seconds(list)} seconds");
    println(f"{list.len()} songs, still here");
}
```

```out
395 seconds
2 songs, still here
```

After the last section you might expect `total_seconds(list)` to move
the list into the function. It doesn't, because of what the parameter
says. Every parameter has a *convention*, which says what the function
does with its argument, and `list: Vec<Song>`, with nothing written
before the type, has the default convention, `let`:

- the function may read the argument, and nothing else: not change it,
  not keep it;
- the argument is not copied: the function reads the caller's list in
  place;
- the caller keeps its value.

A `let` parameter is *lent* to the function for the length of the call
and comes back, unchanged, when the call returns. This is the
convention you'll use most, and it's the default so that the harmless
case is the one you don't have to write.

Since a `let` parameter is read-only, changing one is an error. Here's
a first try at a function that adds a song:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn add(list: Vec<Song>, song: Song) {
    list.push(song);
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    add(list, Song { title: "Blue Moon", seconds: 185 });
    println(f"{list.len()}");
}
```

```err
error[own.readonly]: writes through 'list', a 'let Vec<Song>', which is read-only (let: borrowed to be read)
 --> playlist.vl: line 4, column 5
  = help: take it inout ('x: inout T', called with '&x') to change it | try: volec refactor signature add --type list 'inout Vec<Song>'
```

The help says how to fix it, and that's the next convention.

## inout: changing

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn add(list: inout Vec<Song>, song: Song) {
    list.push(song);
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    add(&list, Song { title: "Blue Moon", seconds: 185 });
    add(&list, Song { title: "Summertime", seconds: 210 });
    println(f"{list.len()} songs");
}
```

```out
2 songs
```

`list: inout Vec<Song>` says that `add` may change the list, and that
the change reaches the caller. At the call, the caller writes `&list`.
The `&` is the point of the whole design: reading `add(&list, ...)`,
you know that this call may change `list`, and that it can't change
anything else you passed it. In vole, you can see from a line of code
which of your variables it may change.

Inside the function, `list` is used as the list itself: `list.push(song)`,
`list.len()`, `list[0]`. There's nothing to dereference. The same goes
for a number:

```vole
fn bump(count: inout i64) {
    count += 1;
}

fn main() {
    var plays = 0;
    bump(&plays);
    bump(&plays);
    println(f"{plays}");
}
```

```out
2
```

The variable you pass with `&` must be one you're allowed to change,
so it's a `var` (or an inout parameter of your own).

The compiler checks the `&` both ways. Leave it off for an inout
parameter:

```vole
fn bump(count: inout i64) {
    count += 1;
}

fn main() {
    var plays = 0;
    bump(plays);
    println(f"{plays}");
}
```

```err
error[conv.marker]: 'plays' is lent inout here (the callee may change it): mark it '&plays'
 --> main.vl: line 7, column 9
  = help: an inout parameter takes '&place'; when the callee never changes it, take it let: 'volec refactor signature F --convention x let'
  = try: volec edit patch main.vl:7 --old '(plays' --new '(&plays'
  = try: volec fix --suggested main.vl
```

Or put one where the function only reads:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn total_seconds(list: Vec<Song>) -> i64 {
    var total = 0;
    for s in list {
        total += s.seconds;
    }
    total
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    println(f"{total_seconds(&list)}");
}
```

```err
error[conv.marker_extra]: '&' marks an argument the callee may change; 'list' is taken let or sink here (read, or moved): pass 'list'
 --> playlist.vl: line 14, column 30
  = try: volec edit patch playlist.vl:14 --old '&list' --new 'list'
  = try: volec fix --suggested playlist.vl
```

Either way, the error names the fix, and `volec fix --suggested` makes
it.

### One change at a time

An inout parameter is *exclusive*: while a function is changing a
value, nothing else may look at it or change it. Here's a function that
moves every song from one list to another, called with the same list
twice:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn append_all(to: inout Vec<Song>, from: inout Vec<Song>) {
    while let Some(s) = from.pop() {
        to.push(s);
    }
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    append_all(&list, &list);
}
```

```err
error[own.conflict]: 'list' is borrowed mutably by '&list' and mutably again by '&list' in the same call
 --> playlist.vl: line 12, column 23
  = help: pass disjoint places ('&a.x, a.y'), copy the plain value out first, or for two elements of one Vec use 'v.swap(i, j)'
```

With `to` and `from` the same list, every pop would make room for a
push, and the loop would never end. The rule that two inout arguments
can't be the same value stops this before it runs. More generally, it
means that inside a function, an inout parameter is the only way to
reach that value. Nothing can change it under the function's feet, and
the function's changes can't surprise anyone else. (It also lets the
compiler optimize: it never has to wonder whether two parameters are
the same memory.)

Passing two *different* parts of one value is fine: `f(&song.seconds,
song.title)` lends one field to be changed and another to be read.

### When the change begins

An inout access begins when the call starts, after every argument has
been worked out. So an argument that only reads the same value, and is
done reading by then, is fine:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn add_copies(list: inout Vec<Song>, n: i64) {
    for i in 0..n {
        list.push(Song { title: "Encore", seconds: 60 + i });
    }
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    add_copies(&list, list.len());
    println(f"{list.len()} songs");
}
```

```out
2 songs
```

`list.len()` runs first, and gives a number, 1. By the time
`add_copies` starts changing the list, nothing else is looking at it.
That's also why `v.push(v.len())` works.

What can't go alongside an inout argument is one that is still looking
at the same value *while the call runs*: a view of it, or a second
inout access, as in `append_all(&list, &list)`. Here `add_all` would
push onto the list while it reads the songs to add from that same list:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn add_all(list: inout Vec<Song>, more: [Song]) {
    for s in more {
        list.push(s);
    }
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    add_all(&list, list[..]);
    println(f"{list.len()} songs");
}
```

```err
error[own.conflict]: 'list' is borrowed mutably by '&list' and viewed by 'list[..]' in the same call
 --> playlist.vl: line 12, column 20
  = help: pass disjoint places ('&a.x, a.y'), copy the plain value out first, or for two elements of one Vec use 'v.swap(i, j)'
```

`list[..]` is a view of all the songs (views come later in this
chapter), and it would still be in use while `add_all` changes the list
under it. The rule is the same as before: while a call may change a
value, nothing else in that call may look at it. Put the songs to add
in a list of their own first, and pass that.

### Keeping an access in a variable

Sometimes you want to change one value through several calls, and give
the access a shorter name. `inout name = &place;` does that:

```vole
fn bump(count: inout i64) {
    count += 1;
}

fn main() {
    var plays = [0, 0, 0];
    inout middle = &plays[1];
    bump(&middle);
    bump(&middle);
    middle += 10;
    println(f"{plays[1]}");
}
```

```out
12
```

`middle` isn't a copy of `plays[1]`: it is `plays[1]`, under another
name, for as long as it is used. It's passed on with `&middle`, and
changed directly with `middle += 10`. While `middle` is in use, `plays`
is reached only through it, by the same exclusivity rule.

## sink: taking

The third convention hands a value over for good. Let's put finished
playlists on a shelf:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn archive(shelf: inout Vec<Vec<Song>>, list: sink Vec<Song>) {
    shelf.push(list);
}

fn main(gpa: Gpa) {
    var shelf: Vec<Vec<Song>> = Vec::new_in(gpa);
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    archive(&shelf, list);
    println(f"{shelf.len()} playlist, {shelf[0].len()} song");
}
```

```out
1 playlist, 1 song
```

`list: sink Vec<Song>` says that `archive` takes the list: the caller's
value moves into the function, which then owns it. The function can
keep it (here, by pushing it onto the shelf, which moves it again),
change it, or let it be dropped when the function ends. Back in `main`,
`list` is dead after the call, exactly as after `let backup = list;`.
Use it again and you get the same `own.moved` error as before, this
time naming the call it moved into.

There's no marker at the call for a sink argument. You can tell from the
parameter, and the compiler tells you if you use the dead variable.

A sink parameter belongs to the function, so the function may change
it, with no `var` needed. Here a function takes a playlist, adds an
encore to it, and hands it back:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn with_encore(list: sink Vec<Song>, encore: Song) -> Vec<Song> {
    list.push(encore);
    list
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    let concert = with_encore(list, Song { title: "Summertime", seconds: 210 });
    println(f"{concert.len()} songs");
}
```

```out
2 songs
```

For a plain value, `sink` and `let` are almost the same: the function
gets a copy, and the caller keeps its own. The difference is that a
sink copy is the function's to change.

Here are the three conventions side by side:

| convention | written | the function | the caller writes | afterwards, the caller's value |
|---|---|---|---|---|
| let | `list: Vec<Song>` | reads it | `total_seconds(list)` | unchanged |
| inout | `list: inout Vec<Song>` | changes it | `add(&list, s)` | changed |
| sink | `list: sink Vec<Song>` | takes it | `archive(&shelf, list)` | moved away (an owned value) |

Choosing is usually easy. Start with `let`. Make it `inout` if the
function has to change the caller's value, and `sink` if it has to keep
the value after it returns (in a struct, a list, another owner).

## Methods and their receivers

A method is a function attached to a type, and its first parameter,
`self`, is the value it's called on, its *receiver*. A receiver has a
convention too, written before `self`:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

struct Playlist { name: str, songs: Vec<Song> }

impl Playlist {
    fn new(name: str, gpa: Gpa) -> Playlist {
        Playlist { name: name, songs: Vec::new_in(gpa) }
    }

    fn len(self) -> i64 {
        self.songs.len()
    }

    fn add(inout self, song: Song) {
        self.songs.push(song);
    }

    fn finish(sink self) -> Vec<Song> {
        println(f"closing {self.name}");
        self.songs
    }
}

fn main(gpa: Gpa) {
    var mix = Playlist::new("Sunday", gpa);
    mix.add(Song { title: "Blue Moon", seconds: 185 });
    mix.add(Song { title: "Summertime", seconds: 210 });
    println(f"{mix.name} has {mix.len()} songs");
    let songs = mix.finish();
    println(f"{songs.len()} songs kept");
}
```

```out
Sunday has 2 songs
closing Sunday
2 songs kept
```

- `fn len(self)` reads the playlist: `self` is a let receiver.
- `fn add(inout self, ...)` changes it.
- `fn finish(sink self)` takes it: after `mix.finish()`, `mix` is dead,
  and its songs have moved out to the caller.

A method call lends its receiver without an `&`: `mix.add(...)`, not
`(&mix).add(...)`. The method's signature says it changes `mix`, and
the name of the method usually does too. Since `add` changes `mix`,
`mix` has to be a `var`.

You've been calling methods like these all along. `Vec`'s `push` is
`fn push(inout self, x: sink T)`: it changes the list and takes the
element.

## Returning values

Look at `Playlist::new` and `finish` again. Each makes or takes an
owned value and returns it. Returning an owned value moves it to the
caller: nothing is copied, and nothing is dropped at the function's
end, because the value has a new owner.

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn sampler(gpa: Gpa) -> Vec<Song> {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    list.push(Song { title: "Summertime", seconds: 210 });
    list
}

fn main(gpa: Gpa) {
    let list = sampler(gpa);
    println(f"{list.len()} songs");
}
```

```out
2 songs
```

This is the normal way to make a value in a function and hand it out.
In some languages, returning a big value is something to avoid; in
vole, it costs the same as returning its small handle.

So prefer returning a result to filling in an `inout` parameter the
caller made empty for you. To return several things, return a tuple or
a struct.

## Views

Not everything is a value with its own memory. Take `opening`, which
gives you the first two songs of a playlist, without copying them:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn opening(list: Vec<Song>) -> [Song] {
    list[0..2]
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    list.push(Song { title: "Blue Moon", seconds: 185 });
    list.push(Song { title: "Summertime", seconds: 210 });
    list.push(Song { title: "Cheek to Cheek", seconds: 300 });
    let start = opening(list);
    println(f"{start.len()} songs, starting with {start[0].title}");
}
```

```out
2 songs, starting with Blue Moon
```

`[Song]` is a *slice*: a view of some songs that something else owns.
A *view* points into memory owned by another value. `list[0..2]` makes
a view of elements 0 and 1 of `list`; nothing is copied. A `str` is a
view too: a string literal like `"Blue Moon"` views text stored in the
program itself, and `String` (chapter 7) is the owned kind of text that
views can point into.

How does the compiler know that `start` views `list`, and not something
else? It works it out from the body of `opening`. For every function,
the compiler computes a short *view summary*: which parameters the
result can point into. It does this the same way it works out the
effects you saw at the end of chapter 2, from the function's code and
the summaries of the functions it calls. You can ask for it:

```console
$ volec query views opening playlist.vl
crate::opening	views(list) inferred
```

`views(list)`: the result points into the argument `list`. So at the
call `opening(list)` in `main`, the compiler knows that `start` views
`main`'s `list`, and it checks `main` with that.

Views are what make vole fast without copying, and they're also where
other languages get into trouble. What if `list` changes while `start`
still views it? A `push` may need more room and move the elements to
new memory, and then `start` would point at memory that has been given
back. In C, that's a use after free, one of the worst bugs there is.
In vole, it's a compile error:

```vole playlist.vl
struct Song { title: str, seconds: i64 }

fn add(list: inout Vec<Song>, song: Song) {
    list.push(song);
}

fn opening(list: Vec<Song>) -> [Song] {
    list[0..2]
}

fn main(gpa: Gpa) {
    var list: Vec<Song> = Vec::new_in(gpa);
    add(&list, Song { title: "Blue Moon", seconds: 185 });
    add(&list, Song { title: "Summertime", seconds: 210 });
    let start = opening(list);
    add(&list, Song { title: "Cheek to Cheek", seconds: 300 });
    println(start[0].title);
}
```

```err
error[own.conflict]: 'add(&list, Song { title: "Cheek to Cheek", seconds: 300 })' may change 'list' while 'start' (playlist.vl: line 15, column 9) views it; 'start' is used at playlist.vl: line 17, column 13
 --> playlist.vl: line 16, column 5
  = help: use the view before the change, keep an index instead of a view, or keep a copy | try: volec query own playlist.vl:17:13
```

It's the same exclusivity rule as before, applied to views: while
`start` views `list` and is still going to be used, `list` can't be
changed. The help lists the usual fixes. Here, the simplest is to use
the view before the change: move the `println` up a line. A view that
is never used again is no conflict, so the change is then fine.

A view also can't outlive what it views. Here's a function that makes
an uppercase copy of a title, and tries to return a view of it:

```vole shout.vl
fn shout(title: str, gpa: Gpa) -> str {
    let loud = title.to_uppercase_in(gpa);
    loud.as_str()
}

fn main(gpa: Gpa) {
    println(shout("Blue Moon", gpa));
}
```

```err
error[own.escape]: 'shout' returns a view of 'loud', which is dropped when 'shout' returns
 --> shout.vl: line 3, column 5
  = help: return the owner itself; a caller that wants a view takes '.as_slice()' of it
```

`loud` is a `String` that `shout` owns, so it's dropped when `shout`
returns, and the view would point at nothing. The fix is to return the
owner instead, moving it out to the caller, as the help says:

```vole shout.vl
fn shout(title: str, gpa: Gpa) -> String {
    title.to_uppercase_in(gpa)
}

fn main(gpa: Gpa) {
    println(shout("Blue Moon", gpa));
}
```

```out
BLUE MOON
```

### Why there are no lifetimes to write

In Rust, a function like `opening` takes a reference and returns one,
and its signature has to say how long the returned reference may live
compared with the one passed in. In the simple cases the compiler fills
that in, and in the others you write it as *lifetimes*: `fn opening<'a>(list:
&'a Vec<Song>) -> &'a [Song]`. In vole you wrote nothing, yet the
compiler caught the conflict in `main`. It didn't need to be told,
for three reasons, all of which you've now seen:

- There are no references to store. A parameter is lent for the call
  and comes back when it ends; nothing in the program holds a pointer
  to someone else's variable that could outlive the call.
- The only things that point into other values are views, and views
  are made only from what the compiler can see: a parameter, a local
  variable, constant data in the program. A view can be kept in a
  variable, a struct field, even a list of views, but the compiler
  follows it wherever it goes, and nothing can keep one in a global
  variable or anywhere else it can't follow.
- What a function's result views is computed from its body, as its
  view summary, so a caller is checked against what the function really
  does.

So the question a lifetime answers in Rust, "how long may this point
into that?", is one the compiler can answer for itself in vole: for as
long as the owner is neither changed nor gone. There's nothing for you
to write, and when there's a problem, the error points at the lines
that conflict and says how to fix them.

## When to clone

`.clone()` makes an independent copy of an owned value, with memory of
its own. Reach for it when you really want two values that will go
their separate ways: a backup before an edit, a starting point you want
to keep.

It's rarely the right fix for an `own.moved` error, though, even if the
`try:` line offers it. Usually the value moved because a function took
it with `sink`, or because you wrote `let w = v;`, when all you needed
was to read it. Then the better fix is to read it in place: pass `v` to
a `let` parameter, which lends it and gives it back, or just keep using
`v` instead of making `w`. A `clone` that's there only to get past the
compiler is a copy your program does on every run.

> **If you know Rust:** `x: T` is like `x: &T`, `x: inout T` like `x:
> &mut T`, and `x: sink T` like taking `T` by value; the receivers are
> `self`, `inout self` and `sink self`. `&x` at a call marks only an
> inout argument, an access is used without `*`, and there are no
> lifetimes. Rust's spellings (`&mut T`, `&mut x`, `let mut`, `*r`) are
> `conv.rust` errors whose `try:` lines write vole's, and `volec fix
> --only conventions` rewrites a whole file of them.

> **If you know Swift:** `inout` with `&` at the call is Swift's idea,
> and the words `let`, `inout` and `sink` come from Hylo, a language
> built on mutable value semantics.

## Summary

This chapter was about how vole shares data without sharing it:

- every value has one owner; plain values (numbers, structs of them)
  are copied by `=`, and owned ones (`Vec`, `String`, a struct with
  one) are moved, leaving the old name dead (`own.moved`);
- an owned value is dropped at the end of its owner's scope, exactly
  once; `drop(x)` drops it early, and `impl Drop` runs code then;
- a parameter's convention says what a function does with it: `let`
  (the default) reads, `inout` changes and is marked `&x` at the call,
  `sink` takes;
- methods take `self`, `inout self` or `sink self`, and a call lends
  the receiver without `&`;
- returning an owned value moves it to the caller;
- a view (`[T]`, `str`) points into what something else owns; the
  compiler keeps it inside its owner (`own.conflict`, `own.escape`) and
  works out each function's view summary, so there are no lifetimes to
  write;
- `.clone()` is for when you really want two values.

With these rules in hand, the next chapter builds types of your own:
structs, enums, and the pattern matching that takes them apart.

## Try it yourself

- Write `fn longest(list: Vec<Song>) -> Song`, which returns the longest
  song. Which convention does `list` need? Why can you return a `Song`
  from it without a `clone`?
- Write `fn remove_short(list: inout Vec<Song>, limit: i64)`, which
  removes the songs shorter than `limit` seconds. (`list.remove(i)`
  removes element `i`; watch your index as the list gets shorter.)
- Add `fn total(self) -> i64` to `Playlist`, and try calling `mix.total()`
  after `mix.finish()`. Read the error, and fix it by moving the call.
