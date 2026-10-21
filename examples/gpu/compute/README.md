# compute: a compute shader, checked against the CPU

For each n below 2^20, the number of steps the Collatz map
(`n -> n/2` or `3n+1`) takes to reach 1, one GPU invocation per n:

```sh
tachyonc main.tach -l objc -o compute && ./compute
```

```text
1048576 numbers, 0 wrong
longest below 1048576: 837799, 524 steps
steps in all: 138299831
```

The program is the whole of std::gpu's compute path, on wgpu's model:

- `gpu::Instance::new_in(gpa)`, `inst.adapter()?`, `adapter.device()?`:
  the device and its queue (`Result`s: a Mac without Metal has no
  adapter).
- `dev.shader(&ShaderSource::msl(text, refl))?`: the shader compiler's
  output for this device's `caps().shader_kind`. Until the WGSL compiler
  lands, the MSL and its `Reflection` (entry points, bindings with their
  Metal slots) are written by hand.
- `dev.compute_pipeline(&shader, "main")?` and `dev.bind_group(
  pipe.bind_layout(0), [...])`: the layout comes from the reflection.
- `enc.compute_pass(|pass| { ... })`: a pass is a closure; it ends when
  the closure returns.
- `queue.submit(enc.finish())`, then `host.map_read(&dev)`: it waits for
  the GPU and returns a view of the buffer's bytes; `gpu::u32s` reads
  them as `u32`s.

Everything is dropped at the end of `main`: buffers, pipelines, the
device. `-l objc` links the Objective-C runtime; std::gpu opens Metal
itself. Misuse (a buffer bound as storage without
`BufferUsage::STORAGE`, a dispatch before its bind group) stops the
program with the rule's code, `gpu.usage`, `gpu.pipeline`.
