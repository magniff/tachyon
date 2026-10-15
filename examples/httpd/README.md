# httpd

A small HTTP file server, a clone of `python -m http.server`: it serves
the files of a directory, and an HTML listing for directories, on
http://127.0.0.1:8000/. Sockets, directory reading and file I/O through
the C library, declared by hand; the HTML and the headers built in
`std::Buf`s with f-strings.

## Build and run

From this folder (with `tachyonc` on your `PATH`, or `../../target/tachyonc`):

```sh
tachyonc main.tach -o httpd
./httpd ..            # serve the examples folder; no argument: the current directory
```

Then open http://127.0.0.1:8000/ in a browser, or:

```sh
curl -i http://127.0.0.1:8000/httpd/README.md
```

Ctrl-C stops it.

## Expected output

The server logs to stderr, one line per request:

```text
Serving /path/to/examples
Serving HTTP on http://127.0.0.1:8000/ ...
GET / 200 (dir)
GET /httpd 301
GET /httpd/ 200 (dir)
GET /httpd/README.md 200 (text/plain; charset=utf-8)
GET /nope 404
```

A directory without a trailing slash is redirected (301) to the URL with
one, as browsers expect; a directory with an `index.html` serves that
file. The test suite only builds it (a server runs until stopped).

## How it works

**Declaring the C library by hand.** Every C function the server uses is
in one `extern "C"` block, with tachyon types for C's (`int` is `i32`,
`size_t` is `u64`, any pointer `*u8`):

```tach
extern "C" {
    fn socket(domain: i32, kind: i32, protocol: i32) -> i32;
    fn accept(fd: i32, addr: *u8, len: *u32) -> i32;
    fn opendir(path: *u8) -> *u8;
    fn readdir(dir: *u8) -> *u8;
    ...
}
```

Declaring them, rather than importing the headers (`import
"sys/socket.h" as c;`, as the `c-libc-tour` example does), keeps the
program independent of the headers of the machine that builds it: the
same source cross-compiles for Linux and macOS from either
(`tachyonc --target x86_64-linux main.tach -o httpd.o`).

**What differs between the systems, at run time.** The module `sys`
holds every difference: the socket constants, `struct sockaddr_in` (BSD
puts a length byte before the family) and `struct dirent`. Each layout is
a `#[repr(C)]` struct, and `uname` decides which one applies:

```tach
#[repr(C)]
struct SockaddrIn { family: u16, port: u16, addr: u32, zero: [u8; 8] }

#[repr(C)]
struct SockaddrInBsd { len: u8, family: u8, port: u16, addr: u32, zero: [u8; 8] }
```

`listen_tcp` returns `Result<i32, [u8]>`: the socket, or the message of
what failed, which `main` prints.

**Raw pointers from C, viewed safely.** `readdir` returns a pointer to an
entry; `sys::dirent` casts it to the system's layout and returns the
name's address and the entry's type. `sys::cstr` turns a C string into a
`[u8]` slice, after which everything is checked tachyon code:

```tach
pub fn cstr(s: *u8) -> [u8] {
    unsafe { s[0..strlen(s) as i64] }
}
```

**Paths for C.** C wants NUL-terminated strings; `Path` keeps a `Buf`
with a 0 at the end and hands out both views: `c()` the `*u8` for C,
`bytes()` the slice without the NUL.

**Responses.** The headers are one f-string per line pushed into a `Buf`,
and sent with one `write` loop:

```tach
h.push_fmt(f"HTTP/1.0 {status}\r\nContent-Type: {content_type}");
if let Some(n) = length {
    h.push_fmt(f"\r\nContent-Length: {n}");
}
```

**Resources freed on every path.** `defer` closes each descriptor and
frees each buffer when its block ends, whichever `return` is taken:

```tach
fn handle_request(fd: i32, system: System, root: [u8]) {
    defer unsafe { close(fd) };
    ...
    let mut path = Path::join(root, url);
    defer path.free();
```

**Small pure helpers** (URL decoding, HTML escaping, the MIME type by
extension) are ordinary safe code over slices, with `match` on bytes and
`Option` for a hex digit that may not be one.

## Language features

- `extern "C"` declarations, `#[repr(C)]` structs, raw pointers: `tachyonc guide c-interop`
- `unsafe` blocks, borrows: `tachyonc guide unsafe`
- inline modules (`mod sys { ... }`), `pub`, `use super::`: `tachyonc guide modules`
- `defer`, `Buf`: `tachyonc guide memory`
- `Result`, `Option`, `if let`: `tachyonc guide conversions`
- f-strings, `push_fmt`, `eprintln`: `tachyonc guide formatting`
