# compute: a compute shader, checked against the CPU

For each n below 2^20, the number of steps the Collatz map
(`n -> n/2` or `3n+1`) takes to reach 1, one GPU invocation per n:

```sh
volec main.vl -o compute && ./compute
```

```text
1048576 numbers, 0 wrong
longest below 1048576: 837799, 524 steps
steps in all: 138299831
```

The program is the whole of std::gpu's compute path, on wgpu's model:

- `gpu::Instance::new_in(gpa)`, `inst.adapter()?.device()?`:
  the device and its queue (`Result`s: a Mac without Metal has no
  adapter).
- `dev.shader(ShaderSource::msl(MSL, refl))?`: a shader for this
  device's `caps().shader_kind`, with its `Reflection` (entry points,
  bindings with their Metal slots). `dev.shader_wgsl(text)` makes both
  from WGSL (as [triangle](../triangle/) does), but the walk climbs past
  2^32 (704511 reaches 56991483520) and WGSL has no 64-bit integers, so
  this kernel is MSL, its `ulong` and its reflection written by hand.
- `dev.compute_pipeline(shader, "main")?` and `dev.bind_group(
  pipe.bind_layout(0), [...])`: the layout comes from the reflection.
- `enc.compute_pass(|pass| { ... })`: a pass is a closure; it ends when
  the closure returns.
- `queue.submit(enc.finish())`, then `host.map_read(dev)`: it waits for
  the GPU and returns a view of the buffer's bytes; `gpu::u32s` reads
  them as `u32`s.

Everything is dropped at the end of `main`: buffers, pipelines, the
device. std::gpu links the Objective-C runtime and opens Metal itself:
no flags to add (`-l objc` was needed before 0.25). Misuse (a buffer
bound as storage without `BufferUsage::STORAGE`, a dispatch before its
bind group) stops the program with the rule's code, `gpu.usage`,
`gpu.pipeline`.
