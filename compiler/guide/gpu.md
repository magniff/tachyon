# GPU: std::gpu (0.22)

`std::gpu` is compute and rendering on the GPU, on wgpu's model: an
`Instance`, an `Adapter`, a `Device` and its `Queue`; `Buffer`s,
`Texture`s and their views, `Sampler`s; a `Shader`, bind groups and
compute and render pipelines; an `Encoder` whose passes are closures.
On macOS it runs on Metal. Link the Objective-C runtime; std opens
Metal itself (no `-framework`):

```sh
volec main.vl -l objc -o prog
```

## Lifecycle

Every object is an owned value (`guide memory`): it is dropped at the
end of its scope, and dropping a resource the GPU still uses is safe
(the submitted work keeps it alive). There is no `free`.

| object | made by | used by |
|---|---|---|
| `Device`, `Queue` | `inst.adapter()?.device()?` | everything below; `queue.submit(cmds)` |
| `Buffer` | `dev.buffer(size, usage)`, `dev.buffer_init(bytes, usage)` | bind groups, copies, `map_read(dev)`, `map_write(dev)` + `unmap(dev)` |
| `Texture`, `TextureView` | `dev.texture(w, h, format, usage: ..)`, `tex.view()` | bind groups, render passes, copies |
| `Shader` | `dev.shader_wgsl(wgsl)?` (WGSL text), or `dev.shader(src)?` with `src` a `ShaderSource::msl(code, reflection)` | pipelines |
| `ComputePipeline`, `RenderPipeline` | `dev.compute_pipeline(shader, "main")?`, `dev.render_pipeline(desc)?` | passes; `pipe.bind_layout(0)` |
| `BindGroup` | `dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..])` | `pass.set_bind_group(0, g)` |
| `Encoder`, `Commands` | `dev.encoder()`, `enc.finish()` | `enc.compute_pass(\|pass\| ..)`, `enc.render_pass(desc, \|pass\| ..)`, copies |

A mapped buffer is a view (`guide views`): `let b = buf.map_read(dev);`
waits for the GPU and views the buffer, which cannot be used while `b`
is. Shaders come from the shader compiler as a `ShaderSource`: the code
for the device's `caps().shader_kind` (MSL on Metal) and its
`Reflection` (entry points, bindings and their native slots).
`dev.shader_wgsl(text)` does it all: `std::gpu::wgsl` translates the
WGSL and its reflection feeds the pipelines (a rejected shader is a
`gpu::Error::Shader` with its `LINE:COL: error wgsl.CODE` line); a
program can also write both by hand, as below.

## Compute

```tach
use std::gpu;
use std::gpu::{BindingType, BufferUsage, Reflection, ShaderSource};

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let code = "kernel void k(device uint* xs [[buffer(0)]], uint i [[thread_position_in_grid]]) { xs[i] = xs[i] * xs[i]; }";
    var refl = Reflection::new_in(gpa);
    refl.compute("main", "k", 64);                         // entry, its MSL name, workgroup
    refl.bind(0, 0, BindingType::Storage, compute: 0);     // @group(0) @binding(0): buffer(0)
    let src = ShaderSource::msl(code, refl);
    let shader = dev.shader(src)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    var xs: Vec<u32> = Vec::new_in(gpa);
    for i in 0..64 { xs.push(i as u32); }
    var buf = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()),
        BufferUsage::STORAGE | BufferUsage::MAP_READ);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1); // one workgroup of 64
    });
    queue.submit(enc.finish());
    let squares = gpu::u32s(buf.map_read(dev));
    println(f"{squares[3]} {squares[63]}");
    Ok(())
}
```
```out
9 3969
```

The same kernel in WGSL: `@group(g) @binding(b)` are the bind groups'
numbers, and a runtime-sized array is bounds-checked against the buffer
bound there.

```tach
use std::gpu;
use std::gpu::BufferUsage;

const SQUARE: [u8] = "@group(0) @binding(0) var<storage, read_write> xs: array<u32>;\n\
    @compute @workgroup_size(64) fn main(@builtin(global_invocation_id) id: vec3<u32>) {\n\
    xs[id.x] = xs[id.x] * xs[id.x];\n\
    }";

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let shader = dev.shader_wgsl(SQUARE)?;
    let pipe = dev.compute_pipeline(shader, "main")?;
    var xs: Vec<u32> = Vec::new_in(gpa);
    for i in 0..64 { xs.push(i as u32); }
    var buf = dev.buffer_init(gpu::bytes_of_u32(xs.as_slice()),
        BufferUsage::STORAGE | BufferUsage::MAP_READ);
    let group = dev.bind_group(pipe.bind_layout(0), [gpu::bind(0, buf)][..]);
    var enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(pipe);
        pass.set_bind_group(0, group);
        pass.dispatch(1);
    });
    queue.submit(enc.finish());
    let squares = gpu::u32s(buf.map_read(dev));
    println(f"{squares[3]} {squares[63]}");
    Ok(())
}
```
```out
9 3969
```

## Render to a texture

```tach
use std::gpu;
use std::gpu::{BufferUsage, Format, PassDesc, Reflection, ShaderSource, TextureUsage};

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, var queue) = inst.adapter()?.device()?;
    let code = "#include <metal_stdlib>\nusing namespace metal;\nvertex float4 vs(uint v [[vertex_id]]) { float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) }; return float4(p[v], 0, 1); }\nfragment float4 fs() { return float4(1, 0.5, 0, 1); }\n";
    var refl = Reflection::new_in(gpa);
    refl.vertex("vs", "vs");
    refl.fragment("fs", "fs");
    let src = ShaderSource::msl(code, refl);
    let shader = dev.shader(src)?;
    let desc = gpu::RenderDesc::new(shader, "vs", "fs", Format::Rgba8Unorm);
    let pipe = dev.render_pipeline(desc)?;
    let tex = dev.texture(8, 8, Format::Rgba8Unorm, usage: TextureUsage::RENDER_ATTACHMENT | TextureUsage::COPY_SRC);
    let view = tex.view();
    var out = dev.buffer(256 * 8, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    var enc = dev.encoder();
    enc.render_pass(PassDesc::color(view), |pass| { // cleared to black, then drawn
        pass.set_pipeline(pipe);
        pass.draw(0..3, 0..1); // a triangle over the whole target
    });
    enc.copy_texture_to_buffer(tex, out, 256); // rows 256 bytes apart
    queue.submit(enc.finish());
    let px = out.map_read(dev);
    println(f"{px[0]} {px[1]} {px[2]} {px[3]}");
    Ok(())
}
```
```out
255 128 0 255
```

## Capabilities

`dev.caps()` says what the device can do: `compute`, `render`,
`surfaces`, `textures`, `unified_memory` (information only: mapping
behaves the same either way) and `shader_kind` (`ShaderKind::Msl`,
`Spirv`, `Ptx`). A compute-only backend reports `render: false`, and
every render, texture and surface call `requires` its flag
(`gpu.unsupported`). Backends implement `std::gpu::hal::Api` (and
`hal::Render` when they draw); the API never depends on one's memory
model.

## Contracts

Misuse stops the program at the call, `FILE:LINE:COL: gpu.CODE: ...`,
exit 101 (`guide contracts`); what can fail however correct the program
is (no adapter, a shader the driver rejects) is a `gpu::Error`.

| code | the rule | the fix |
|---|---|---|
| `gpu.usage` | a buffer or texture used without the usage flag that allows it | add it at creation: `BufferUsage::STORAGE \| BufferUsage::COPY_SRC` |
| `gpu.align` | offsets: 256 for uniform and storage bindings, 4 for copies; rows 256 | `dev.align_uniform(n)` |
| `gpu.range` | an offset, size or draw range past its buffer or texture | the sizes |
| `gpu.layout` | a bind group that does not match the pipeline's layout | make it from `pipe.bind_layout(i)` |
| `gpu.pipeline` | a draw or dispatch without a pipeline or a bind group it uses | `pass.set_pipeline`, `pass.set_bind_group` |
| `gpu.format` | a format that does not fit: target, view, storage, shader kind | the pipeline's target format |
| `gpu.limits` | a size or count above `dev.limits()` | smaller |
| `gpu.state` | a buffer used while mapped for writing | `buf.unmap(dev)` first |
| `gpu.unsupported` | a capability the device lacks | check `dev.caps()` |

Surfaces (`inst.surface(dev, RawSurface::MetalLayer(layer))`,
`surf.configure(..)`, `surf.frame()?`, `frame.present(&queue)`) are
what std::window draws into; `RawSurface::Headless` gives frames without
a window.
