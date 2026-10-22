# 3. Values, types, functions and control flow

The guessing game in chapter 2 used a little of everything. This
chapter slows down and goes through the building blocks one at a time:
variables, numbers and the other simple types, functions, blocks, and
loops. None of it is exotic, and much of it will look familiar from
other languages, but vole has a few habits of its own (wrapping
integers, `as` for conversions, labels without quotes), and it's worth
meeting them early.

Our running example is a small unit converter that grows as the
chapter goes: a function, then a table, then a loop that asks how long
savings take to double, and finally a little prime counter.

## Variables

You met both kinds of variable in chapter 2. A `let` gives a name to a
value that won't change; a `var` makes one that can:

```vole
fn main() {
    let rate = 3;
    var total = 0;
    total += rate;
    total += rate;
    println(f"{total}");
}
```

```out
6
```

Prefer `let`. Most values in a program are computed once and then only
read, and a `let` tells the reader (and the compiler) that this one
won't change under them. Change a `let` by mistake and the compiler
says so, and how to fix it:

```vole
fn main() {
    let total = 0;
    total += 3;
    println(f"{total}");
}
```

```err
error[type error]: cannot assign to immutable variable 'total'
 --> main.vl: line 3, column 5
  = help: make it mutable: `var total`
```

### Shadowing

You can declare a new variable with the same name as an old one. The
new one *shadows* the old: from that line on, the name means the new
variable.

```vole
fn main() {
    let width = "42";
    let width = width.len();
    let width = width * 10;
    println(f"{width}");
}
```

```out
20
```

Each `let width` is a separate variable, and the second one even has a
different type: the first is text, the others are numbers. Shadowing is
handy when you transform a value in steps and the old steps are no
longer interesting. It's not the same as changing a `var`: nothing is
changed, a new name is made.

### Every variable starts with a value

There's no way to declare a variable now and give it a value later.
`let x;` is an error. When you don't know the value yet, that's usually
a sign to compute it with an expression, like the `if` and `match`
expressions you'll see below. This rule means a vole program can never
read a variable that was never set.

> **If you know Rust:** `var` is `let mut`, and `let mut` is an error
> whose `try:` line rewrites it to `var`.

## Numbers

Vole has signed integers `i8`, `i16`, `i32`, `i64` and unsigned ones
`u8`, `u16`, `u32`, `u64`, named by their size in bits, plus `isize`
and `usize`, which are the size of a pointer (64 bits on every platform
vole runs on). Floating-point numbers are `f32` and `f64`.

You'll use two of these most of the time: `i64` for whole numbers and
`f64` for fractional ones. They are what vole picks when nothing says
otherwise:

```console
$ volec try '6 * 7'
i64 = 42
$ volec try '7.0 / 2.0'
f64 = 3.5
```

Lengths and indexes are `i64` too. A list's `len()` is an `i64`, and
you index with an `i64`. There's no separate unsigned type for sizes,
so you never have to convert between "a count" and "a number".

### Literals

A number can be written in several ways. Underscores are ignored, so
use them to group digits. `0x` starts a hexadecimal number and `0b` a
binary one. A suffix gives a literal a type of its own:

```vole
fn main() {
    let million = 1_000_000;
    let mask = 0xff;
    let flags = 0b1010;
    let small = 7u8;
    let half = 0.5f32;
    println(f"{million} {mask} {flags} {small} {half}");
}
```

```out
1000000 255 10 7 0.5
```

Most of the time you won't need suffixes: a literal takes the type its
surroundings need. In `let b: u8 = 7;` the 7 is a `u8`, and in `x + 1`
with `x` a `u32`, the 1 is a `u32`. But it has to fit:

```vole
fn main() {
    let b: u8 = 300;
    println(f"{b}");
}
```

```err
error[type error]: integer literal 300 does not fit in type 'u8'
 --> main.vl: line 2, column 17
  = help: 'u8' holds 0..=255: a wider type (`i64`), or the literal's low bits with `as` (`LITERAL as u8`)
```

### Converting with `as`

Arithmetic happens between values of one type. A smaller integer
converts to a bigger one by itself, because nothing can be lost: an
`i32` goes wherever an `i64` is wanted, and a `u8` wherever a `u32` is.
That's called *widening*. Every other conversion you write yourself,
with `as`:

```vole
fn main() {
    let x: i32 = 5;
    let y: i64 = 7;
    let z: i32 = x + y;
    println(f"{z}");
}
```

```err
error[type error]: expected 'i32', got 'i64'
 --> main.vl: line 4, column 22
  = help: only widening is implicit: convert explicitly
  = try: y as i32
  = try: volec fix --suggested main.vl
```

`x + y` is an `i64` (the `i32` widened), and putting an `i64` into an
`i32` could lose its high bits, so the compiler wants you to say so. The
first `try:` line is the code to write in place of `y`: `let z: i32 = x
+ y as i32;`. The second is a command that makes that edit for you.

`as` also converts between integers and floats. Converting a float to
an integer drops the fraction:

```vole
fn main() {
    let price = 3.99;
    let cents: i64 = 250;
    println(f"{price as i64} {cents as f64 / 100.0}");
}
```

```out
3 2.5
```

> **If you know C:** nothing narrows or changes signedness without an
> `as`. An `int` quietly becoming a `char`, or a negative number
> quietly becoming a huge unsigned one, can't happen.

### Every operation has an answer

What is `i64::MAX + 1`? What is `7 / 0`? In many languages the answer is
"it depends": a crash, an exception, or (in C) *undefined behaviour*,
where the program may do anything at all, and may do something
different when you turn on optimizations. Vole gives every operation a
defined answer:

```vole
fn main() {
    let big = i64::MAX;
    let small: u8 = 250;
    println(f"{big + 1}");
    println(f"{small + 10}");
    println(f"{7 / 0} {7 % 0}");
    println(f"{-7 / 2} {-7 % 2}");
    println(f"{1e30 as i64} {-1.5 as i64}");
}
```

```out
-9223372036854775808
4
0 7
-3 -1
9223372036854775807 -1
```

Line by line:

- Integers *wrap*: one past the largest `i64` is the smallest one, and
  a `u8` that goes past 255 starts again at 0. This is how the hardware
  works, and it's what you want for hashes and checksums.
- Dividing by zero gives 0, and the remainder by zero is the number
  itself.
- Integer division rounds towards zero, and the remainder takes the
  sign of the number divided.
- A float too big for an integer *saturates*: it becomes the largest
  value the type holds.

Why not stop the program on overflow, as some languages do? Because
then every `+` would be a possible stop, and the compiler couldn't
treat arithmetic as ordinary arithmetic. Instead, every operation means
one thing, the same at every optimization level, and a program never
has undefined behaviour from its numbers. When overflow would be a bug
in your program, check for it, or state it as a requirement (chapter 6
shows a first `requires`).

`i64::MAX`, `i64::MIN`, `u8::MAX` and so on are constants, one pair for
each integer type. Numbers have no methods, though: `x.abs()` and
`x.pow(2)` don't exist. Write the expression instead (`if x < 0 { -x }
else { x }`), or a small function of your own.

> **If you know Rust:** overflow never panics, in debug builds or
> release ones; `x / 0` is 0; lengths are `i64`, not `usize`.

## Other simple types

### bool

`bool` is `true` or `false`. Comparisons (`==`, `!=`, `<`, `<=`, `>`,
`>=`) give one, and `&&`, `||` and `!` combine them. `!` works only on
a `bool`; flipping the bits of an integer is `~`:

```vole
fn main() {
    let warm = 25 > 20;
    println(f"{warm && !false} {~5}");
}
```

```out
true -6
```

A condition must be a `bool`: `if count { ... }` is an error, write `if
count != 0`. Comparisons don't chain either: `0 < x < 10` is an error,
write `0 < x && x < 10`.

### Characters are bytes

`'a'` is a `u8`: one byte, the character's ASCII code. Vole has no
`char` type yet; text is UTF-8, and chapter 7 shows how to work with
it. A byte prints as a number, unless you format it with `:c`:

```vole
fn main() {
    let letter = 'a';
    println(f"{letter} {letter:c} {(letter + 1):c}");
}
```

```out
97 a b
```

### Tuples

A *tuple* groups a few values of any types. Its parts are `.0`, `.1` and
so on, or you can take it apart with a `let`:

```vole
fn main() {
    let city = ("Oslo", 59.9, 709000);
    println(f"{city.0} is at latitude {city.1}");
    let (name, _, people) = city;
    println(f"{name} has {people} people");
}
```

```out
Oslo is at latitude 59.9
Oslo has 709000 people
```

The `_` in the pattern means "a part I don't want a name for". Tuples
are good for returning two or three values from a function. For more
than that, or for anything that gets passed around, a struct with named
fields reads better (chapter 5).

### Arrays

An array holds a fixed number of values of one type. `[31, 28, 31, 30]`
is an array of four `i64`s, of type `[i64; 4]`, and `[0; 8]` is eight
zeros. Index it with `[i]`, starting from 0:

```vole
fn main() {
    let days = [31, 28, 31, 30];
    var leap = days;
    leap[1] = 29;
    println(f"{days[1]} {leap[1]} {days.len()}");
}
```

```out
28 29 4
```

An array is a value, like a number. `var leap = days;` copies all four
elements, so changing `leap` leaves `days` alone. (Chapter 4 is all
about what `=` does, and this is the simple case.)

Every index is checked. Ask for an element that isn't there and the
program stops with a message:

```vole
fn main() {
    let days = [31, 28, 31, 30];
    let month = 4;
    println(f"{days[month]}");
}
```

```out exit=101
main.vl:4:16: index out of bounds: index 4, length 4
```

That's a panic, as in chapter 2: the program prints where it stopped
and why, and exits with status 101. It never reads memory past the end
of the array.

> **If you know C:** arrays don't turn into pointers. `=` copies the
> whole array, and passing one to a function passes the value.

### The unit type

Some expressions have no interesting value: an assignment, a call to a
function that returns nothing, a block that ends in a statement. Their
type is `()`, called *unit*, and its only value is also written `()`. A
function without `->` returns `()`. You'll mostly meet it in error
messages, as in the next sections.

## Functions

Back to the converter. Start a file, `convert.vl`:

```vole convert.vl
fn celsius_to_fahrenheit(c: f64) -> f64 {
    c * 9.0 / 5.0 + 32.0
}

fn main() {
    let body = 37.0;
    println(f"{body} C is {celsius_to_fahrenheit(body)} F");
}
```

```out
37 C is 98.6 F
```

A function lists its parameters in parentheses, each with its type,
and its result type after `->`. Its body is a block, and the value of
the block's last expression is what the function returns. There's no
`return` here because none is needed. (The `37.0` prints as `37`: a
float prints as the shortest text that reads back as the same number.)

`return` is for leaving early:

```vole
fn sign(n: i64) -> i64 {
    if n == 0 {
        return 0;
    }
    if n < 0 { -1 } else { 1 }
}
```

Functions can be declared in any order, and they're always declared at
the top level of a file: there are no functions inside functions.

### Default and named arguments

A parameter can have a default value, used when the caller leaves the
argument out. Let's add a question to the converter: at a given
interest rate, how many years until savings double?

```vole convert.vl
fn celsius_to_fahrenheit(c: f64) -> f64 {
    c * 9.0 / 5.0 + 32.0
}

fn years_to_double(start: f64, rate: f64 = 0.05) -> i64 {
    var balance = start;
    var years = 0;
    while balance < 2.0 * start {
        balance = balance * (1.0 + rate);
        years += 1;
    }
    years
}

fn main() {
    println(f"37 C is {celsius_to_fahrenheit(37.0)} F");
    println(f"at 5%: {years_to_double(1000.0)} years");
    println(f"at 7%: {years_to_double(1000.0, rate: 0.07)} years");
}
```

```out
37 C is 98.6 F
at 5%: 15 years
at 7%: 11 years
```

The first call leaves `rate` out, so it is 0.05. The second names it:
`rate: 0.07`. Naming an argument is optional, but it makes a call with
several numbers much easier to read. Named arguments come after the
positional ones, in the order the parameters are declared.

(The `while` loop is new; we'll come to it in a moment.)

### Parameters are read-only

Inside `years_to_double`, `start` and `rate` can't be changed: a
parameter is read-only unless the function says otherwise. That's why
the loop keeps its running total in a `var balance` of its own. How a
function can change what it's given, or take it over completely, is the
subject of the next chapter.

## Blocks are expressions

You've seen that a function's body has a value: its last expression.
That's true of every block in braces, and of `if`:

```vole
fn main() {
    let temperature = 31;
    let advice = if temperature > 30 {
        "stay inside"
    } else if temperature > 15 {
        "go for a walk"
    } else {
        "bring a coat"
    };
    let doubled = {
        let t = temperature * 2;
        t + 1
    };
    println(f"{advice} {doubled}");
}
```

```out
stay inside 63
```

`if` picks a branch, and the value of that branch is the value of the
whole `if`. So `advice` gets one of the three strings, and there's no
need for a `var` set in each branch. Each branch has to give a value of
the same type, and the `else` is required (without it, what would the
value be when the condition is false?).

The block after `let doubled =` makes a temporary `t`, which exists
only inside the braces, and ends with `t + 1`, its value.

### The stray semicolon

What makes the last expression the block's value is that it has no `;`
after it. A semicolon turns an expression into a statement, whose value
is thrown away. Put one at the end of a function by habit, and the
function no longer returns anything:

```vole
fn add_one(x: i64) -> i64 {
    x + 1;
}

fn main() {
    println(f"{add_one(1)}");
}
```

```err
error[type error]: function 'add_one' body has type '()', expected 'i64'
 --> main.vl: line 1, column 27
```

The body's value is `()`, the unit type, because it ends in a statement.
The function promised an `i64`. When you see "has type '()'" in an
error, look for a semicolon after the value you meant to return.

> **If you know Rust:** this is all the same as in Rust, including the
> stray-semicolon mistake. There is no `?:`; `if` is the expression.

## Loops

Vole has three loops: `while`, `for` and `loop`.

### while

`while` repeats its body as long as a condition holds. `years_to_double`
above uses one: it grows the balance until it is twice the start.

### for and ranges

`for` goes through the values of a *range*, a list, or anything else
that can be gone through one value at a time. A range `a..b` is the
numbers from `a` up to, but not including, `b`; `a..=b` includes `b`.
Let's print a table of temperatures:

```vole convert.vl
fn celsius_to_fahrenheit(c: f64) -> f64 {
    c * 9.0 / 5.0 + 32.0
}

fn main() {
    for step in 0..5 {
        let c = step * 10;
        let f = celsius_to_fahrenheit(c as f64);
        println(f"{c:>4} C = {f:>6.1} F");
    }
}
```

```out
   0 C =   32.0 F
  10 C =   50.0 F
  20 C =   68.0 F
  30 C =   86.0 F
  40 C =  104.0 F
```

`step` is 0, 1, 2, 3 and 4 in turn. In the f-string, `{c:>4}` prints `c`
right-aligned in four columns, and `{f:>6.1}` prints `f` in six columns
with one decimal. (Chapter 7 has the rest of the format specs.)

To count down, reverse the range with `.rev()` (`1..4` is 1, 2 and 3;
for now `.rev()` works on `a..b` ranges, not on `a..=b` ones):

```vole
fn main() {
    for i in (1..4).rev() {
        print(f"{i}... ");
    }
    println("go!");
}
```

```out
3... 2... 1... go!
```

The same `for` goes through an array's elements:

```vole
fn main() {
    var total = 0;
    for d in [31, 28, 31] {
        total += d;
    }
    println(f"{total}");
}
```

```out
90
```

### loop, with a value

`loop` repeats forever, until a `break`. You saw it in the guessing
game. A `break` can also carry a value out of the loop, which makes the
whole `loop` an expression:

```vole
fn main() {
    var n = 1;
    let first = loop {
        n += 1;
        if n * n > 200 {
            break n;
        }
    };
    println(f"{first} is the first number whose square is over 200");
}
```

```out
15 is the first number whose square is over 200
```

### Labels

`break` and `continue` act on the innermost loop. To act on an outer
one, give it a *label*: a name and a colon before the loop. Then `break
:name` or `continue :name` refers to it. Here's the last piece of our
example, a prime counter. For each candidate, an inner loop tries
divisors; finding one means the candidate isn't prime, so we skip
straight to the next candidate:

```vole primes.vl
fn main() {
    var count = 0;
    var largest = 0;
    candidates: for n in 2..50 {
        for d in 2..n {
            if d * d > n {
                break;
            }
            if n % d == 0 {
                continue :candidates;
            }
        }
        count += 1;
        largest = n;
    }
    println(f"{count} primes below 50, the largest is {largest}");
}
```

```out
15 primes below 50, the largest is 47
```

The plain `break` leaves the inner loop: once `d * d > n`, there's no
point trying bigger divisors. The `continue :candidates` abandons the
inner loop and the rest of the outer body, and goes on to the next `n`,
so `count += 1` runs only for primes.

> **If you know Rust:** labels have no quote. Rust's `'outer: for` and
> `break 'outer` are `outer: for` and `break :outer` in vole; the quoted
> form gets an error whose `try:` line respells it.

## Comments and constants

A `//` comment runs to the end of the line. A `/* ... */` comment can
span lines, and comments of that kind nest, so you can comment out code
that already has one in it:

```vole
// A comment on its own line.
const FREEZING: f64 = 32.0; // a comment after code

/* A block comment,
   /* with one nested inside, */
   still going. */
fn boiling() -> f64 {
    FREEZING + 180.0
}

fn main() {
    println(f"water boils at {boiling()} F");
}
```

```out
water boils at 212 F
```

`const` declares a constant: a name for a value that is known when the
program is compiled. A constant has a type written out, its name is
written in capitals by convention, and it can be used anywhere in the
file, before or after it is declared. Use constants for the numbers
that would otherwise be unexplained in your code: `const MAX_GUESS: i64
= 100;` reads better than a bare `100` in three places.

There is also `static var`, a variable that lives as long as the
program and is visible to every function. It is rarely what you want:
a value passed as a parameter is easier to follow, and chapter 14
explains why threads and statics don't mix.

## Summary

This chapter went through the basics:

- `let` for values that don't change, `var` for ones that do, and
  shadowing with a second `let`;
- the integer and float types, `i64` and `f64` as the defaults, and
  `i64` for lengths and indexes;
- literals with underscores, `0x`, `0b` and suffixes, widening, and `as`
  for every other conversion;
- defined behaviour for every operation: wrapping, `x / 0 == 0`,
  saturating conversions;
- `bool`, bytes as `u8`, tuples, arrays with checked indexing, and `()`;
- functions, their results, default and named arguments;
- blocks and `if` as expressions, and the stray semicolon;
- `while`, `for` over ranges and arrays, `loop` with `break value`, and
  labels;
- comments and `const`.

So far every value has been simple: a number, a tuple, an array. The
next chapter is about values that own memory, like the `String` in the
guessing game, and about how functions read, change and take them. It
is the chapter that makes vole different from what you know.

## Try it yourself

- Add `fahrenheit_to_celsius` to the converter, and print a second table
  going the other way, from 0 to 100 F in steps of 20.
- Give `years_to_double` a third parameter, `target: f64 = 2.0`, so it
  can answer "how long until my savings triple?", and call it with a
  named argument.
- Change the prime counter to stop (with a `break :candidates`) as soon
  as it has found ten primes, and print the tenth.
