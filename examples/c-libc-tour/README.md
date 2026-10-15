# c-libc-tour

A walk through the C library from tachyon, using nothing but the
system's own headers: the environment (`setenv`, `getenv`, `unsetenv`),
time (`gmtime`, `localtime`, `strftime`, `mktime`, `tzset`), files
(`fopen`, `fwrite`, `chmod`, `mkdir`, `mkdtemp`) and directories
(`opendir`, `readdir`, `stat`, `unlink`, `rmdir`). The C structs involved
(`struct tm`, `struct stat`, `struct dirent`) differ between macOS and
Linux; `import` reads them from the headers of the system the program is
compiled for, so one source fits both.

With arguments, it lists those directories instead, like a small `ls -l`.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or as
`../../target/tachyonc` from a built tree):

```sh
tachyonc main.tach -o c-libc-tour && ./c-libc-tour
./c-libc-tour /etc ~       # list directories instead
```

Everything it calls is in the C library, so it links as it is on macOS
and Linux. `import` needs a C compiler that can preprocess the target's
headers: building for your own machine always works; cross-compiling
for Linux from a Mac needs `TACHYON_CC` set to a cross C compiler with a
Linux sysroot (the compiler says so when it is missing).

## Expected output

The tour prints the same text on every run and system: it uses a fixed
moment, sets its own time zones, and makes (then removes) its own
directory.

```
== environment
TOUR_GREETING = Some("hello from setenv")
TOUR_MISSING  = None
PATH is set: true
== time
1234567890 is Friday, 13 February 2009, 23:31:30 UTC
  struct tm: year 2009, month 2, day 44 of the year, weekday 5
  UTC0      2009-02-13 23:31:30 +0000  (UTC+0:00)
  JST-9     2009-02-14 08:31:30 +0900  (UTC+9:00)
  NPT-5:45  2009-02-14 05:16:30 +0545  (UTC+5:45)
  <-03>3    2009-02-13 20:31:30 -0300  (UTC-3:00)
100 days later: 2009-05-24, a Sunday (8640000 seconds later)
== files
made three files and a directory: true
the directory: 4 entries
-rw-r--r--     12  data.csv
-rw-r--r--      0  empty
-rw-------     17  notes.txt
drwxr-xr-x  <dir>  subdir/
total 29 bytes in files
removed it again: true
```

A directory it cannot open is reported on stderr:

```
$ ./c-libc-tour /no/such/directory
cannot open /no/such/directory
```

## How it works

### Seven headers, one `c`

```tach
import "stdlib.h" as c;
import "time.h" as c;
import "dirent.h" as c;
import "sys/stat.h" as c;
// ... stdio.h, string.h, unistd.h
```

Every imported header adds to one C module, here called `c`: functions
(`c::readdir`), structs (`c::tm`, `c::stat`, `c::dirent`, `c::DIR`,
`c::FILE`), and integer macros as constants (`c::S_IFMT`, `c::S_IFDIR`).
The declarations are those of the target's libc: on macOS `struct stat`
has `st_birthtimespec` and a 16-bit `st_mode`, on Linux neither, and the
program never has to know. `tachyonc --emit-imports main.tach -o
decls.tach` writes out what the headers gave, as tachyon source.

What headers cannot give: function-like macros (`S_ISDIR(m)`: the example
writes `is_dir` with `S_IFMT` instead), `static inline` functions, and
`errno` (a macro over `__error()` on macOS, `__errno_location()` on
Linux).

### Tachyon text and C strings

C wants NUL-terminated strings; a tachyon `[u8]` slice is a pointer and a
length with no NUL. Two small helpers cross the line, each with one
direction:

```tach
// tachyon -> C: copy the bytes and a 0 into a Buf; pass .as_slice().ptr
fn cstring(s: [u8], gpa: Gpa) -> Buf {
    let mut b = Buf::new_in(gpa);
    b.push_str(s);
    b.push(0);
    b
}

// C -> tachyon: copy the C string into a Buf of our own
unsafe fn owned(p: *u8, gpa: Gpa) -> Buf {
    let mut b = Buf::new_in(gpa);
    b.push_cstr(p);
    b
}
```

Copying out matters: `readdir` reuses its `struct dirent`, and a later
`setenv` may move what `getenv` returned. A `Buf` belongs to the program,
and is freed explicitly (`defer b.free();`), as tachyon has no
destructors.

### getenv: NULL becomes None

```tach
fn env(name: [u8]) -> Option<Buf> {
    let mut cname = cstring(name);
    defer cname.free();
    let p = unsafe { c::getenv(cname.as_slice().ptr) };
    if p == 0 as *u8 { None } else { Some(unsafe { owned(p) }) }
}
```

The unsafe C call is wrapped once; the rest of the program uses a safe
function with a tachyon type. `{greeting:?}` prints the `Option<Buf>`
with Debug: `Some("hello from setenv")`.

### Time: struct tm, strftime, TZ

```tach
let mut utc: c::tm = unsafe { *c::gmtime(&when) };
let mut long = format_time("%A, %d %B %Y, %H:%M:%S UTC", &utc);
```

`gmtime` and `localtime` return a pointer to a static `struct tm` inside
the C library; `*` copies it into a tachyon local, after which it is
ours. `&when` passes the address of an `i64` where C wants a `time_t *`.
`format_time` calls `strftime` into a stack array (`[u8; 128]`, passed as
`&out as *u8`) and keeps the `n` bytes it wrote.

`localtime` follows the `TZ` environment variable, which `tzset` rereads.
The zones are POSIX strings (`JST-9`: a name and the offset *west* of
UTC), which need no time zone database, so the output is the same on a
minimal Linux container. `mktime` goes the other way and normalizes: day
113 of February 2009 is the 24th of May.

### Directories: opendir, readdir, stat

```tach
let d = unsafe { c::opendir(cdir.as_slice().ptr) };
if d == 0 as *c::DIR {
    return None;
}
defer unsafe { c::closedir(d); };
loop {
    let ent = unsafe { c::readdir(d) };
    if ent == 0 as *c::dirent {
        break;
    }
    let name_ptr = unsafe { &ent.d_name as *u8 };
    ...
}
```

`DIR` is whatever the header says it is; the program only holds a
pointer. `defer` closes the directory on every way out of the function.
`d_name` is a `char` array inside the struct: `&ent.d_name as *u8` is its
address, a C string. `readdir` returns names in the file system's order,
so the entries are sorted with a closure:
`entries.sort_by(|a, b| { ... x.cmp(&y) })`.

`stat` fills a `struct stat` the program has to provide. Its fields
differ between systems, so it is not written out field by field but
made of zero bytes:

```tach
unsafe fn zeroed_stat() -> c::stat {
    let p = c::calloc(1, size_of(c::stat) as u64) as *c::stat;
    let value = *p;
    c::free(p as *u8);
    value
}

let mut st: c::stat = unsafe { zeroed_stat() };
if unsafe { c::stat(path.as_slice().ptr, &st) } == 0 {
    e.size = st.st_size;
    e.mode = st.st_mode; // u16 on macOS, u32 on Linux: it widens
}
```

A generic `zeroed<T>()` would do this for any C struct, and works when
compiling to an object or an executable; tachyon 0.15's assembly output
(`-o x.s`) cannot yet name an instance of a generic function at a C type
(its symbol holds the C module's `<c>`), so the example keeps to one
type. Assigning
`st.st_mode` to a `u32` field compiles on both systems because integer
widening (`u16` to `u32`) is implicit and lossless; narrowing would need
`as`.

### Files, and permissions without octal

`write_file` opens with `fopen`, writes the slice with
`fwrite(text.ptr, 1, text.len as u64, f)` (a slice needs no NUL when its
length goes along), and sets the mode with `chmod` so the umask does not
change the output. Tachyon has no octal literals, so `0755` is written
`0x1ed` in a named constant. `mkdtemp` writes the random part of the
name into its template, so the template is a `Buf` of the program's, not
a read-only `c"..."` literal.

## C interop rules in brief

- **Declaring C**: `import "header.h" as c;` brings the system's
  declarations; `extern "C" { ... }` declares by hand. All C calls are
  `unsafe`.
- **Structs from headers** are `#[repr(C)]` structs with the target's
  layout; use their fields by name, never by offset.
- **Pointers from C** are raw: compare with `0 as *T` for NULL, and read
  through them only inside `unsafe`. Turn NULL into `None` at the
  boundary.
- **Strings**: `c"..."` for literals; copy `[u8]` into a NUL-terminated
  buffer for C; copy C strings out (`Buf::push_cstr`) before C reuses
  them.
- **Memory**: whatever C allocates, C frees (`closedir`, `free`); whatever
  tachyon allocates (`Buf`, `Vec`), tachyon frees, typically with `defer`.
- **Linking**: all of this is libc, which `tachyonc -o prog` links.

## Language features

- `import "x.h" as c`, C structs and constants, `c"..."`, C strings:
  `tachyonc guide c-interop`
- `unsafe fn` with a contract, raw pointers, `&x as *u8`:
  `tachyonc guide unsafe`
- `defer`, `Buf`, freeing explicitly: `tachyonc guide memory`
- `Option` at the boundary, `{x:?}` on an `Option<Buf>`:
  `tachyonc guide conversions`, `tachyonc guide formatting`
- `sort_by`, `filter`, `map`, `sum` with closures:
  `tachyonc guide iterators`, `tachyonc guide closures`
- implicit widening (`u16` to `u32`): `tachyonc guide conversions`
