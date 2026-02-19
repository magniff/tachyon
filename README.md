# The Tachyon Programming Language

Target: x86-64 Linux, System V AMD64 ABI **only**

In addition to the Rust toolchain, you will need the following third-party dependencies:

- nasm - used to assemble the generated .asm file into an object file
- gcc - used to link the object file against libc

These tools are required by the tachyon.sh script to produce a final executable.

```
$ ./tachyon.sh examples/helloworld.tach -o helloworld
    Finished `release` profile [optimized] target(s) in 0.01s
[1/3] tachyon  examples/helloworld.tach → examples/helloworld.asm
[2/3] nasm     examples/helloworld.asm → examples/helloworld.o
[3/3] gcc      examples/helloworld.o → helloworld  (libc)
done: helloworld

$ ./helloworld
Hello from tachyon!
```

WIP, stay tunned
