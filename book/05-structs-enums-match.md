# 5. Structs, enums and pattern matching

So far our programs have worked with numbers, text and lists. Real
programs have their own kinds of data: a player with a position, a
command the player typed, a shape, a token, a setting. This chapter
shows how to define types of your own and how to work with them.

By the end of it you'll be able to define *structs*, which group named
fields, and *enums*, which say a value is one of several cases, each
case with its own data. You'll take them apart with `match`, and see
why the compiler insists that a `match` covers every case, and how that
helps when your program grows.

The running example is the beginning of a tiny text adventure: a
player who walks between rooms, and the commands they type.

## Structs

A struct is a value with named fields. Let's make a player:

```vole adventure.vl
struct Player { room: i64, moves: i64 }

fn main() {
    var player = Player { room: 0, moves: 0 };
    player.room = 1;
    player.moves += 1;
    println(f"room {player.room}, {player.moves} moves");
}
```

```out
room 1, 1 moves
```

The `struct` line declares the type: its name, then each field with its
type. `Player { room: 0, moves: 0 }` is a *struct literal*: it makes a
`Player`, with a value for every field. `player.room` reads a field, and
since `player` is a `var`, you can assign to a field too.

Every field needs a value. Forget one and the compiler says which:

```vole adventure.vl
struct Player { room: i64, moves: i64 }

fn main() {
    let player = Player { room: 0 };
    println(f"room {player.room}");
}
```

```err
error[type error]: missing field 'moves' in struct 'Player' constructor
 --> adventure.vl: line 4, column 18
```

When a variable has the same name as a field, you can leave out the
`name:` part. `Player { room, moves }` means `Player { room: room,
moves: moves }`:

```vole
struct Player { room: i64, moves: i64 }

fn main() {
    let room = 2;
    let moves = 5;
    let a = Player { room, moves };
    let b = Player { room: 2, moves: 5 };
    println(f"{a == b}");
}
```

```out
true
```

`==` compares two structs field by field. It works on any struct whose
fields can be compared, with nothing to declare.

Remember the two kinds of values from chapter 4. A struct made of plain
fields, like `Player`, is plain: `let b = a;` copies it. A struct with
a `Vec` or a `String` in it is owned: `let b = a;` moves it, and it is
dropped field by field when its owner goes away. You never say which;
the fields decide.

## Methods

Functions that belong to a type go in an `impl` block:

```vole adventure.vl
struct Player { room: i64, moves: i64 }

impl Player {
    fn new() -> Player {
        Player { room: 0, moves: 0 }
    }

    fn describe(self) {
        println(f"You are in room {self.room}, after {self.moves} moves.");
    }

    fn walk_to(inout self, room: i64) {
        self.room = room;
        self.moves += 1;
    }
}

fn main() {
    var player = Player::new();
    player.describe();
    player.walk_to(2);
    player.describe();
}
```

```out
You are in room 0, after 0 moves.
You are in room 2, after 1 moves.
```

There are two kinds of functions here:

- `describe` and `walk_to` are *methods*: their first parameter is
  `self`, the value they're called on, and you call them with a dot,
  `player.describe()`. As chapter 4 showed, `self` reads the player,
  `inout self` changes it (so `player` must be a `var`), and `sink
  self` would take it.
- `new` has no `self`. It's an *associated function*: it belongs to the
  type but isn't called on a value, and you call it with the type's
  name, `Player::new()`. A function called `new` that makes a value is
  a convention, not a rule; the compiler treats it like any other.

Inside an `impl`, `Self` is another name for the type, so `fn new() ->
Self` would mean the same. A type can have several `impl` blocks, which
is handy for grouping methods, and they can be anywhere in the file.

## Enums

A struct is this field *and* that field. Often you need the other kind
of type: this case *or* that case. That's an *enum*. The simplest enums
just list their cases, called *variants*:

```vole
enum Direction { North, South, East, West }
```

A `Direction` is exactly one of those four. You write a variant with
the enum's name in front, `Direction::North`.

Variants can carry data, and different variants can carry different
data. Here are the commands our player can type:

```vole
enum Direction { North, South, East, West }

enum Command {
    Go(Direction),
    Take { item: str },
    Look,
    Quit,
}
```

- `Go(Direction)` carries a direction, by position, like a tuple:
  `Command::Go(Direction::North)`.
- `Take { item: str }` carries a named field, like a struct:
  `Command::Take { item: "lamp" }`.
- `Look` and `Quit` carry nothing.

That's something a struct can't express well. With a struct, you'd have
a `kind` field plus a `direction` and an `item` that make sense only for
some kinds, and nothing would stop you from reading the wrong one. With
an enum, a `Command::Look` simply has no item to read.

When you use an enum's variants a lot, you can import them, and then
write them without the prefix:

```vole
use Direction::{North, South};

enum Direction { North, South, East, West }

fn opposite_of_north() -> Direction {
    South
}

fn is_north(d: Direction) -> bool {
    d == North
}
```

> **If you know C or Go:** an enum with data is a *tagged union*: the
> tag says which variant it is, and the compiler checks the tag every
> time you look inside, so you can't read the data of the wrong variant.

## match

To find out which variant a value is and get at its data, you `match`
on it:

```vole
enum Direction { North, South, East, West }

enum Command {
    Go(Direction),
    Take { item: str },
    Look,
    Quit,
}

fn explain(c: Command) -> str {
    match c {
        Command::Go(Direction::North) => "walk north",
        Command::Go(_) => "walk somewhere else",
        Command::Take { item } => item,
        Command::Look => "look around",
        Command::Quit => "stop playing",
    }
}

fn main() {
    println(explain(Command::Go(Direction::North)));
    println(explain(Command::Go(Direction::West)));
    println(explain(Command::Take { item: "lamp" }));
    println(explain(Command::Quit));
}
```

```out
walk north
walk somewhere else
lamp
stop playing
```

A `match` has *arms*, each a *pattern*, `=>`, and an expression. The
arms are tried in order, and the first one whose pattern fits the value
runs. Patterns can do several things at once:

- `Command::Look` fits that variant;
- `Command::Go(Direction::North)` looks inside: it fits only a `Go`
  carrying `North`. Patterns *nest* as deeply as the data does;
- `_` fits anything, and doesn't name it. `Command::Go(_)` is any
  other `Go`;
- `Command::Take { item }` fits any `Take` and names its field `item`,
  so the arm can use it. That's a *binding*, and it's how you read a
  variant's data: there is no `c.item`.

Like `if`, a `match` is an expression, and each arm gives a value of the
same type. Here, every arm is a `str`, and the `match` is the body's
last expression, so it's what `explain` returns.

### More patterns

Patterns aren't only for enums. You can match numbers, tuples and
`bool`s too, with a few more tricks:

```vole
fn moves_message(moves: i64) -> str {
    match moves {
        0 => "You haven't moved yet.",
        1 | 2 => "You're just getting started.",
        3..=9 => "You know your way around.",
        n if n % 10 == 0 => "A round number of moves!",
        _ => "You've been everywhere.",
    }
}

fn main() {
    for m in [0, 2, 5, 20, 21] {
        println(moves_message(m));
    }
}
```

```out
You haven't moved yet.
You're just getting started.
You know your way around.
A round number of moves!
You've been everywhere.
```

- `1 | 2` fits either one;
- `3..=9` fits any number in that range;
- `n if n % 10 == 0` binds the number to `n`, then runs a *guard*: the
  arm fits only if the condition holds;
- `_` takes everything left.

Tuples make it easy to match on two things at once. Here's the map of
our adventure, matched on a pair of the current room and a direction:

```vole
enum Direction { North, South, East, West }

fn next_room(room: i64, d: Direction) -> i64 {
    match (room, d) {
        (0, Direction::North) => 1,
        (1, Direction::South) => 0,
        (0, Direction::East) => 2,
        (2, Direction::West) => 0,
        _ => room,
    }
}
```

From the hall (room 0), north leads to the kitchen (1) and east to the
garden (2). Any other move leaves you where you are.

### Strings aren't patterns

One thing you can't match on is text. `match word { "north" => ... }`
is an error; compare with `==` instead:

```vole
enum Direction { North, South, East, West }

fn direction(word: str) -> Direction {
    if word == "north" {
        Direction::North
    } else if word == "south" {
        Direction::South
    } else if word == "east" {
        Direction::East
    } else {
        Direction::West
    }
}
```

Patterns in vole are about the shape of a value: which variant, which
number, which tuple. A string has no shape in that sense, just bytes,
so it's compared like any other piece of data. This may change in a
later release.

## Exhaustiveness

A `match` has to cover every possible value. Leave a variant out:

```vole
enum Direction { North, South, East, West }

enum Command {
    Go(Direction),
    Take { item: str },
    Look,
    Quit,
}

fn verb(c: Command) -> str {
    match c {
        Command::Go(_) => "go",
        Command::Take { .. } => "take",
        Command::Look => "look",
    }
}

fn main() {
    println(verb(Command::Look));
}
```

```err
error[type error]: non-exhaustive match: 'Command::Quit' is not covered
 --> main.vl: line 11, column 5
  = help: add an arm for it (try:), or a wildcard arm '_ =>'
  = try: Command::Quit => VALUE,
```

The error names the variant you forgot, and its `try:` line is the arm
to add, with `VALUE` for you to fill in. (`Command::Take { .. }` is a
pattern that fits a `Take` without naming its fields: `..` means "the
rest of the fields, which I don't need".)

This check is more useful than it first looks. Suppose that later we
let the player drop things, and add a variant:

```vole
enum Direction { North, South, East, West }

enum Command {
    Go(Direction),
    Take { item: str },
    Drop { item: str },
    Look,
    Quit,
}

fn verb(c: Command) -> str {
    match c {
        Command::Go(_) => "go",
        Command::Take { .. } => "take",
        Command::Look => "look",
        Command::Quit => "quit",
    }
}

fn is_move(c: Command) -> bool {
    match c {
        Command::Go(_) => true,
        Command::Take { .. } | Command::Look | Command::Quit => false,
    }
}

fn main() {
    println(f"{verb(Command::Look)} {is_move(Command::Quit)}");
}
```

```err
error[type error]: non-exhaustive match: 'Command::Drop { .. }' is not covered
 --> main.vl: line 12, column 5
  = help: add an arm for it (try:), or a wildcard arm '_ =>'
  = try: Command::Drop { .. } => VALUE,
error[type error]: non-exhaustive match: 'Command::Drop { .. }' is not covered
 --> main.vl: line 21, column 5
  = help: add an arm for it (try:), or a wildcard arm '_ =>'
  = try: Command::Drop { .. } => VALUE,
```

The compiler has just listed every place in the program that has to
decide what dropping means. In a big program, that list is exactly the
to-do list you'd otherwise have to find by searching and hoping. It's a
good reason to avoid `_ =>` arms on your own enums when you can: a `_`
silently swallows the new variant, and the compiler can't remind you.

When there are many matches to update, `volec refactor variant` adds
the variant and an arm to every match in one checked step; chapter 17
shows it.

## Option: a value that might not be there

One enum is so useful that it's in the prelude: `Option`. An
`Option<i64>` is either `Some(n)`, holding an `i64`, or `None`, holding
nothing. It's how vole says "there may be no value here", in place of
the null pointer or the special value -1 that other languages use.

It's an ordinary enum, so you match on it like any other:

```vole
enum Direction { North, South, East, West }

fn next_room(room: i64, d: Direction) -> Option<i64> {
    match (room, d) {
        (0, Direction::North) => Some(1),
        (1, Direction::South) => Some(0),
        (0, Direction::East) => Some(2),
        (2, Direction::West) => Some(0),
        _ => None,
    }
}

fn main() {
    match next_room(0, Direction::West) {
        Some(r) => println(f"you walk into room {r}"),
        None => println("you can't go that way"),
    }
}
```

```out
you can't go that way
```

Now the map can say "there's no way through" instead of quietly
keeping you in place. Because `None` is a variant, the compiler makes
you handle it: you can't use the room number without first saying what
happens when there isn't one. Chapter 6 is about `Option` and its
cousin `Result` in depth.

## if let, while let and let else

A full `match` is a lot of ceremony when you care about one case.
`if let` runs a block when a pattern fits:

```vole
fn main() {
    let found: Option<i64> = Some(3);
    if let Some(room) = found {
        println(f"found room {room}");
    } else {
        println("nothing found");
    }
}
```

```out
found room 3
```

`while let` loops for as long as a pattern fits. Popping a list returns
an `Option`, `None` once it's empty, so this empties a list:

```vole
fn main(gpa: Gpa) {
    var path: Vec<i64> = Vec::new_in(gpa);
    path.push(0);
    path.push(1);
    path.push(2);
    while let Some(room) = path.pop() {
        print(f"{room} ");
    }
    println("back at the start");
}
```

```out
2 1 0 back at the start
```

And `let ... else` takes a value apart when the pattern fits, and runs
the `else` block when it doesn't. The `else` block must leave (with
`return`, `break` or `continue`), so after the line, the names are
always there. It's the tidiest way to write "get this, or give up":

```vole
fn first_word(line: str) -> str {
    let Some((word, _)) = line.split_once(" ") else {
        return line;
    };
    word
}

fn main() {
    println(first_word("take lamp"));
    println(first_word("look"));
}
```

```out
take
look
```

`line.split_once(" ")` returns an `Option` of a pair: the text before
the first space and the text after it, or `None` if there is no space.

## The adventure

Here's everything together: a game you can play from standard input,
as in chapter 2. `parse` turns a line into a `Command`, and `apply`
carries it out. `#[derive(Debug)]` on a type lets you print it with
`{c:?}` in an f-string, which is a quick way to see what your code is
working with:

```vole adventure.vl
use std::io;
use std::io::BufReader;

#[derive(Debug)]
enum Direction { North, South, East, West }

#[derive(Debug)]
enum Command {
    Go(Direction),
    Take { item: str },
    Look,
    Quit,
}

struct Player { room: i64, moves: i64, lamp: bool }

impl Player {
    fn new() -> Player {
        Player { room: 0, moves: 0, lamp: false }
    }

    fn describe(self) {
        let name = match self.room {
            0 => "the hall",
            1 => "the kitchen",
            _ => "the garden",
        };
        println(f"You are in {name}.");
    }

    // Returns false when the game is over.
    fn apply(inout self, c: Command) -> bool {
        match c {
            Command::Go(d) => match next_room(self.room, d) {
                Some(r) => {
                    self.room = r;
                    self.moves += 1;
                    self.describe();
                }
                None => println("You can't go that way."),
            },
            Command::Take { item } => {
                if item == "lamp" && self.room == 1 && !self.lamp {
                    self.lamp = true;
                    println("Taken.");
                } else {
                    println(f"There is no {item} here.");
                }
            }
            Command::Look => self.describe(),
            Command::Quit => return false,
        }
        true
    }
}

fn next_room(room: i64, d: Direction) -> Option<i64> {
    match (room, d) {
        (0, Direction::North) => Some(1),
        (1, Direction::South) => Some(0),
        (0, Direction::East) => Some(2),
        (2, Direction::West) => Some(0),
        _ => None,
    }
}

fn parse(line: str) -> Option<Command> {
    if line == "look" {
        return Some(Command::Look);
    }
    if line == "quit" {
        return Some(Command::Quit);
    }
    let Some((verb, rest)) = line.split_once(" ") else {
        return None;
    };
    if verb == "take" {
        return Some(Command::Take { item: rest });
    }
    if verb != "go" {
        return None;
    }
    let d = if rest == "north" {
        Direction::North
    } else if rest == "south" {
        Direction::South
    } else if rest == "east" {
        Direction::East
    } else if rest == "west" {
        Direction::West
    } else {
        return None;
    };
    Some(Command::Go(d))
}

fn main(gpa: Gpa) {
    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    var player = Player::new();
    player.describe();
    loop {
        line.clear();
        if input.read_line(&line).unwrap() == 0 {
            break;
        }
        let Some(c) = parse(line.trim()) else {
            println("I don't understand.");
            continue;
        };
        println(f"> {c:?}");
        if !player.apply(c) {
            break;
        }
    }
    println(f"You made {player.moves} moves.");
}
```

Here's a short game:

```in
go north
take lamp
go west
dance
go south
go east
quit
```

```out
You are in the hall.
> Go(North)
You are in the kitchen.
> Take { item: "lamp" }
Taken.
> Go(West)
You can't go that way.
I don't understand.
> Go(South)
You are in the hall.
> Go(East)
You are in the garden.
> Quit
You made 3 moves.
```

A few things to notice:

- `apply`'s outer `match` has an arm, `Command::Go(d)`, whose value is
  itself a `match`. Matches nest like any other expression.
- In the `Quit` arm, `return false` leaves the whole method. Its type
  is "never returns", so it fits in an arm whose neighbours are `()`.
- A `Command::Take` holds a `str`, a view of the line the player typed
  (chapter 4). That's fine, because each command is used up before the
  next `line.clear()` changes the line.
- The `// Returns false...` line is a comment above a method; that's
  how vole code documents an item.

## Enums as numbers

Sometimes an enum stands for a number in a file format or a protocol.
`#[repr(u8)]` stores it as a `u8`, and `= N` gives each variant its
number:

```vole light.vl
#[repr(u8)]
enum Light { Dark = 0, Dim = 1, Bright = 2 }

fn main() {
    let l = Light::Dim;
    println(f"{l as i64}");
    let n = 2;
    let back = n as Light;
    if back == Light::Bright {
        println("bright");
    }
    let bad = 7 as Light;
    println(f"{bad as i64}");
}
```

```out exit=101
1
bright
light.vl:12:15: invalid value 7 for enum Light
```

`as` converts both ways. From an enum to a number it can't fail. From a
number to an enum it's checked: 7 isn't any `Light`, and rather than
make a `Light` that isn't one of its variants, the program stops with a
panic, naming the line.

## Summary

You can now define your own types:

- structs with named fields, struct literals (and the `{ room, moves }`
  shorthand), field access and assignment, and `==` field by field;
- methods with `self`, `inout self` and `sink self` in `impl` blocks,
  and associated functions like `Player::new()`;
- enums whose variants carry nothing, data by position, or named
  fields;
- `match` with variants, nested patterns, `_`, bindings, `|`, ranges,
  guards and tuples, and `..` to leave fields out;
- exhaustive matches, and how they find every place a new variant
  needs handling;
- `Option`, `if let`, `while let` and `let ... else`;
- `#[repr(u8)]` enums and checked conversions from numbers;
- `#[derive(Debug)]` and `{x:?}`.

`Option` was the first glimpse of how vole handles things that can go
wrong. The next chapter is about that: `Option`, `Result`, the `?`
operator, and panics.

## Try it yourself

- Add a `Drop { item: str }` command. Let the compiler tell you every
  place that needs to handle it, and make dropping the lamp work.
- Add a fourth room, the cellar, below the kitchen, reached with `go
  down`. You'll need a new `Direction` variant; what does the compiler
  say about `next_room`?
- Make `look` in the garden say something different when the player has
  the lamp.
