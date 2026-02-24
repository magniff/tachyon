# The Tachyon Programming Language

Target: x86-64 Linux, System V AMD64 ABI **only**

In addition to the Rust toolchain, you will need the following third-party dependencies:

- nasm - used to assemble the generated .asm file into an object file
- gcc - used to link the object file against libc

These tools are required by the tachyon.sh script to produce a final executable.

```
$ ./tachyon.sh run examples/helloworld.tach
[1/3] tachyon  examples/helloworld.tach → /tmp/tmp.9c6fgQIp8U/helloworld.asm
[2/3] nasm     /tmp/tmp.9c6fgQIp8U/helloworld.asm → /tmp/tmp.9c6fgQIp8U/helloworld.o
[3/3] gcc      /tmp/tmp.9c6fgQIp8U/helloworld.o → /tmp/tmp.9c6fgQIp8U/helloworld.bin  (libc)
running: examples/helloworld.tach
Hello from tachyon!
```

WIP, stay tunned
