# 2. A guessing game

Let's write a real program. It's a classic: the computer picks a number
between 1 and 100, you guess, and it tells you whether your guess is
too small or too big until you get it right.

The game is small, but it touches a lot of vole: reading input,
variables, text, numbers, decisions, loops, errors, and a library
module. This chapter moves fast and explains each idea only as far as
the game needs. Don't worry if something feels unexplained; the
chapters after this one go through every idea properly, and this one
points to them as it goes.

We'll build the game in four steps, running it after each one.

## Step 1: reading a guess

Start a new file, `guess.vl`, with a program that asks for a guess,
reads it and prints it back:

```vole guess.vl
use std::io;
use std::io::BufReader;

fn main(gpa: Gpa) {
    println("Guess the number!");
    println("Please input your guess.");

    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    input.read_line(&line).unwrap();

    println(f"You guessed: {line.trim()}");
}
```

Build it and run it. When it waits, type a number and press Enter:

```console
$ volec guess.vl -o guess
ok: built guess
```

```text
$ ./guess
Guess the number!
Please input your guess.
42
You guessed: 42
```

There is quite a lot in these few lines. Let's go through them.

### Using the standard library

```vole skip
use std::io;
use std::io::BufReader;
```

Vole comes with a standard library, `std`, organized in modules.
`std::io` is the module for input and output. The first line makes it
available under its last name, `io`, so we can write `io::stdin()`.
The second brings one item from that module, `BufReader`, into scope by
name.

In chapter 1 we used `println` without any `use` line, because it's in
the prelude, the handful of names every file gets for free. Everything
else in the standard library is imported like this, one name at a
time. Vole has no way to import "everything from a module": every name a
file uses is either defined in it, imported by name, or written out as
a path like `std::io::stdin`. When you read vole code, you can always
find where a name comes from.

### The allocator

```vole skip
fn main(gpa: Gpa) {
```

This `main` takes a parameter: `gpa`, of type `Gpa`, the program's
*general-purpose allocator*. An allocator is where memory comes from.
The text you type has to be stored somewhere, and its length isn't
known in advance, so the program needs memory it can grow.

In many languages, memory comes from a hidden global allocator that
any function can use. Vole doesn't have one. A program gets its
allocator as a parameter of `main`, and passes it to whatever needs
memory. That makes it visible in the code which parts of a program
allocate, and it lets you choose a different allocator for some part of
it. Chapter 8 is all about this; for now, `fn main(gpa: Gpa)` is how
a program that needs memory starts.

### Variables

```vole skip
    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
```

These two lines make variables. A variable made with `var` can change
later; one made with `let` cannot. We'll be changing both of these, so
they are `var`s.

`io::stdin()` is the program's standard input: what you type, or what
another program sends it. `BufReader::new` wraps it in a reader that
reads in large blocks and hands out a line at a time. (`Type::name` is
how you call a function that belongs to a type; `new` is the usual name
for one that makes a value.)

`line` is a `String`, a growable piece of text. `String::new_in(gpa)`
makes an empty one that gets its memory from `gpa`. The `_in` at the end
of the name is a convention you'll see all over the standard library:
it marks a function that allocates, and it takes the allocator as its
last argument.

What happens if you forget the allocator? Here's a program that tries:

```vole
fn main() {
    var line = String::new();
    line.push_str("hi");
    println(line);
}
```

```err
error[type error]: allocation is explicit: pass an allocator (try: String::new_in(gpa))
 --> main.vl: line 2, column 16
  = help: main takes the allocator: `fn main(gpa: Gpa)`, passed down as a parameter
  = try: volec fix --only alloc016 main.vl
```

The error says what to write instead, and its `help:` line says where
the allocator comes from. Many vole errors end with `try:` lines like
these. They are meant to be used as they are: either code to put where
the error is, or a command to run. `volec fix` is a command that
rewrites code for you; we'll meet it properly in chapter 17.

### Reading the line

```vole skip
    input.read_line(&line).unwrap();
```

`read_line` reads one line from the input and appends it to `line`.

Look at the `&` in `&line`. In vole, a function can't change a value
you pass it unless it says so in its signature, and when it does, the
call site says so too, with `&`. Reading this line, you know that
`read_line` will change `line`, and that's the only argument it may
change. Leave the `&` out and the compiler stops you:

```vole guess.vl
use std::io;
use std::io::BufReader;

fn main(gpa: Gpa) {
    println("Guess the number!");
    println("Please input your guess.");

    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    input.read_line(line).unwrap();

    println(f"You guessed: {line.trim()}");
}
```

```err
error[conv.marker]: 'line' is lent inout here (the callee may change it): mark it '&line'
 --> guess.vl: line 10, column 20
  = help: an inout parameter takes '&place'; when the callee never changes it, take it let: 'volec refactor signature F --convention x let'
  = try: volec edit patch guess.vl:10 --old '(line' --new '(&line'
  = try: volec fix --suggested guess.vl
```

"Inout" is vole's word for a parameter the function may change. The
error also says how to fix it: put the `&` back. (The first `try:` line
is a command that makes exactly that edit; the second fixes every
error in the file that has an exact fix.)

This idea, that functions say what they do with their arguments, is at
the heart of vole. Chapter 4 explains it, along with `let` and `var`.

> **If you know Rust:** `&line` here is not a reference. Vole has no
> references to store or lifetimes to write. A parameter is read
> (the default), changed (`inout`, marked `&` at the call) or taken
> (`sink`). Rust's `&mut line` would be an error with a `try:` line
> that writes `&line`.

Reading can fail: the input might be closed, or a disk might fail.
So `read_line` doesn't return the number of bytes it read directly. It
returns a `Result`, a value that is either `Ok` with the number in it
or `Err` with an error. `.unwrap()` takes the number out of an `Ok`, and
stops the program with an error message if it's an `Err`. That's
the right choice for a first program; chapter 6 shows how to handle
errors properly.

### Printing with an f-string

```vole skip
    println(f"You guessed: {line.trim()}");
```

A string with an `f` in front is an *f-string*: each `{...}` in it is
replaced by the value of the expression inside. `line.trim()` is
`line` without the spaces and the newline around it. (When you type a
number and press Enter, the Enter is part of the line.)

## Step 2: comparing with a secret

Now let's give the game a secret number and compare the guess with it.
For the moment, the secret is always 42. Random numbers come in the
last step; a fixed number makes the game much easier to test.

```vole guess.vl
use std::io;
use std::io::BufReader;

fn main(gpa: Gpa) {
    println("Guess the number!");
    let secret = 42;

    println("Please input your guess.");
    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    input.read_line(&line).unwrap();

    let guess = line.trim().parse::<i64>().unwrap();
    println(f"You guessed: {guess}");

    if guess < secret {
        println("Too small!");
    } else if guess > secret {
        println("Too big!");
    } else {
        println("You win!");
    }
}
```

If you type 50, it says:

```in
50
```

```out
Guess the number!
Please input your guess.
You guessed: 50
Too big!
```

`let secret = 42;` makes a variable that never changes, so it's a
`let`. Its type is `i64`, a 64-bit signed integer: vole picks `i64` for
a whole number unless something says otherwise.

The line we read is text, and we want to compare numbers, so we
convert it:

```vole skip
    let guess = line.trim().parse::<i64>().unwrap();
```

`parse::<i64>()` reads the text as an `i64`. The `::<i64>` part says
which type to parse into; you'll see this form, called a *turbofish*,
whenever a function needs to be told a type. Parsing can fail too (what
if the user types "seven"?), so `parse` returns a `Result` as well, and
we `unwrap` it.

Then `if`, `else if` and `else` pick one of three messages. A
condition doesn't need parentheses around it, but the braces around
each branch are required.

### When unwrap stops the program

What happens if you type something that isn't a number? Let's ask the
shell to type it for us, using a pipe:

```console
$ volec guess.vl -o guess
ok: built guess
$ echo seven | ./guess
Guess the number!
Please input your guess.
guess.vl:13:17: called unwrap on Err
$ echo $?
101
```

`parse` returned an `Err`, and `unwrap` stopped the program. The message
gives the file, line and column of the `unwrap` that failed, and the
program exits with status 101, which in vole always means "stopped by
a failed check". A failure like this is called a *panic*.

A panic is not a crash. Vole checks the things that could go wrong in a
program (an index past the end of a list, an `unwrap` of an error), and
stops cleanly with a message when one does, instead of reading or
writing memory it shouldn't. We'll handle bad input properly in the next step.

## Step 3: guessing until you win

One guess isn't much of a game. Let's keep asking until the guess is
right, and deal with input that isn't a number instead of stopping:

```vole guess.vl
use std::io;
use std::io::BufReader;

fn main(gpa: Gpa) {
    println("Guess the number!");
    let secret = 42;

    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    var tries = 0;

    loop {
        println("Please input your guess.");
        line.clear();
        if input.read_line(&line).unwrap() == 0 {
            println(f"Giving up? The number was {secret}.");
            return;
        }

        let guess = match line.trim().parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                println("That's not a number. Try again.");
                continue;
            }
        };
        tries += 1;

        if guess < secret {
            println("Too small!");
        } else if guess > secret {
            println("Too big!");
        } else {
            println(f"You win! It took you {tries} tries.");
            break;
        }
    }
}
```

Here's a game where the player guesses 50, then 25, then types "seven"
by mistake, then guesses 42:

```in
50
25
seven
42
```

```out
Guess the number!
Please input your guess.
Too big!
Please input your guess.
Too small!
Please input your guess.
That's not a number. Try again.
Please input your guess.
You win! It took you 3 tries.
```

Let's look at what's new.

### loop, break and continue

```vole skip
    loop {
        ...
    }
```

`loop` repeats its body forever, until something leaves it. `break`
leaves the loop: we break when the player wins. `continue` skips the
rest of the body and starts the next round: we continue when the input
isn't a number. And `return` leaves the whole function, which for
`main` means the program ends.

Vole also has `while` and `for` loops; chapter 3 shows them.

### Reusing the line

`line.clear()` empties `line` at the start of each round, because
`read_line` *adds* to what's already there. We make `line` once,
before the loop, and reuse its memory every time.

### The end of the input

`read_line` returns how many bytes it read. Zero means there is nothing
more to read: the input has ended. That happens when input comes from a
file or a pipe, or when you press Ctrl-D in a terminal. Without that
check, the loop would ask forever, so we print the secret and leave.

### match

```vole skip
        let guess = match line.trim().parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                println("That's not a number. Try again.");
                continue;
            }
        };
```

Instead of unwrapping the result of `parse`, we look at it with
`match`. A `match` compares a value against *patterns*, one per arm,
and runs the arm that fits.

- `Ok(n) => n` fits when parsing worked. It names the number inside `n`,
  and the arm's value is `n`.
- `Err(_) => { ... }` fits when parsing failed. The `_` means we don't
  care what the error was. This arm prints a message and continues the
  loop, so it never produces a value at all.

The whole `match` is an expression: its value is the value of the arm
that ran, and that's what `guess` is set to. Vole checks that a match
covers every possible case; leave out the `Err` arm and the program
won't compile. Chapter 5 is about `match` and the types it works best
with.

### Counting tries

`var tries = 0;` starts a counter, and `tries += 1;` adds one to it.
Because it changes, it's a `var`. If you made it a `let`, the compiler
would tell you:

```vole
fn main() {
    let tries = 0;
    tries += 1;
    println(f"{tries}");
}
```

```err
error[type error]: cannot assign to immutable variable 'tries'
 --> main.vl: line 3, column 5
  = help: make it mutable: `var tries`
```

## Step 4: a random secret

A game whose answer is always 42 gets old quickly. The standard
library has a random number generator in `std::random`. Here is the
finished game:

```vole guess.vl
use std::io;
use std::io::BufReader;
use std::random::Xoshiro256pp;

fn main(gpa: Gpa) {
    println("Guess the number!");
    var rng = Xoshiro256pp::from_entropy();
    let secret = rng.random_range_i64(1, 101);

    var input = BufReader::new(io::stdin());
    var line = String::new_in(gpa);
    var tries = 0;

    loop {
        println("Please input your guess.");
        line.clear();
        if input.read_line(&line).unwrap() == 0 {
            println(f"Giving up? The number was {secret}.");
            return;
        }

        let guess = match line.trim().parse::<i64>() {
            Ok(n) => n,
            Err(_) => {
                println("That's not a number. Try again.");
                continue;
            }
        };
        tries += 1;

        if guess < secret {
            println("Too small!");
        } else if guess > secret {
            println("Too big!");
        } else {
            println(f"You win! It took you {tries} tries.");
            break;
        }
    }
}
```

Only two lines changed, besides the new `use` line:

```vole skip
    var rng = Xoshiro256pp::from_entropy();
    let secret = rng.random_range_i64(1, 101);
```

`Xoshiro256pp` is the name of a fast random number generator (the
algorithm is called xoshiro256++). `from_entropy()` starts it from
random data the operating system provides, so every game is different.
`random_range_i64(1, 101)` gives a number from 1 up to, but not
including, 101.

`rng` is a `var` because drawing a number changes the generator's
state, so the next number is different.

Here's one game. Yours will have a different secret, of course:

```text
$ ./guess
Guess the number!
Please input your guess.
50
Too big!
Please input your guess.
25
Too small!
Please input your guess.
37
Too big!
Please input your guess.
31
Too small!
Please input your guess.
34
You win! It took you 5 tries.
```

### What the compiler knows about your program

Here's a preview of something vole does that most languages don't. The
compiler works out what each function may do, and it will tell you:

```console
$ volec query effects main guess.vl
crate::main	alloc(Gpa) io global panic diverge
```

That one line says `main` allocates memory from a `Gpa`, does
input and output, uses some global state (`println` keeps its output
buffer in one), may panic (all those `unwrap`s), and may never return
(the `loop`). You never wrote any of that down: the compiler worked it
out from the code. Chapter 12 shows how to use this, and how to make the compiler
hold a function to a promise such as "this never allocates".

## Summary

You wrote a complete program, and on the way you met:

- `use` lines, which bring standard library names into scope by name;
- `fn main(gpa: Gpa)`, the allocator, and the `_in` functions that use
  it;
- `let` for values that stay put, `var` for ones that change;
- `&` at a call, marking the argument the function may change;
- `Result`, `unwrap`, and `match` on `Ok` and `Err`;
- f-strings;
- `if`/`else`, `loop`, `break`, `continue` and `return`;
- panics: clean stops with a message and exit status 101.

The next chapter starts going through these ideas one at a time, with
the basics: values, types, functions and control flow.

## Try it yourself

- Make the game print "Way too big!" when the guess is more than 20
  above the secret.
- Count the invalid inputs too, and print both counts at the end.
- Make the range a constant at the top of the file: `const MAX: i64 =
  100;`, and use it in `random_range_i64` and in the opening message.
