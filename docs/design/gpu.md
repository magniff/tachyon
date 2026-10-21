# tachyon 0.22 design: GPU support (`std::gpu`)

I read the language from the worktree of branch design-022 (from
night-final: 0.16.0 plus the 0.17 work merged so far) through `tachyonc
guide unsafe|effects|closures|rust`, `guide --find extern|import`,
docs/grammar.md ("Unsafe code", "Layout, conventions and C", "Importing C
headers", "Modules"), `query show front::cpp::directives::include`,
`query items front::modules::stdsections`, main.tach's option parsing,
tests/run.sh's directives and examples/c-qsort, c-mixed-build and httpd.
The 0.17 design (branch design-017b, docs/design/value-semantics.md) is
the model for this document's form and the source of the ownership rules
it depends on; the 0.19 design (branch design-019, docs/design/arch.md)
is the source of `has`. I ran six spikes on today's compiler (§1.2) and
probed the linux/arm64 container (§1.3). I modified nothing but this file
and docs/design/terminal.md (0.23).

The user is away and asked for autonomous work through 0.23: every choice
below is taken as recommended and listed in the last section.

## 1. The current state

### 1.1 What tachyon has for this today

- **C interop is exact and opt-in.** `extern "C"` blocks, `#[repr(C)]`
  types with C's layout, `extern "C" fn` definitions usable as callbacks,
  and AAPCS64 for every argument and result: aggregates in registers or
  memory, homogeneous float aggregates, the indirect result register.
  The ABI fuzzer runs in every gate.
- **One C symbol, many signatures.** `#[link_name = "objc_msgSend"]` on
  several declarations gives each Objective-C selector shape its own
  typed prototype. On arm64 this is exactly how `objc_msgSend` must be
  called: it is a trampoline that keeps every argument register and x8,
  and Apple's headers require a cast to the method's exact type.
- **`import "h" as c`** runs tachyon's own C preprocessor and parser
  (front/cpp, front/cimport) over C headers. It has no framework lookup:
  `import "CoreText/CoreText.h"` fails with `header not found`.
- **Linking:** `-l`, `-L`, objects and C files are passed to `cc` in
  order. `-framework NAME` is rejected (`error: cannot read -framework`),
  so programs that use Apple frameworks link with `cc` by hand.
- **No multi-line string literal and no `include_str`.** A shader is one
  long `c"...\n..."` line today.
- **No threads.** Statics are safe because there is one thread (guide
  unsafe). Any C callback on another thread breaks that assumption.
- **No `Drop`, no `&mut`, no contracts yet.** Resources are freed by hand
  with `defer x.free()`, receivers are `self: *T`, and validation is
  written as `if` plus `panic`.
- **std is one module in sections** (front/modules/stdsections): only the
  sections a program reaches are lexed. There are no std submodules on
  disk and no library search path: a program's modules must sit under its
  root.
- **Allocation is explicit (0.16).** `fn main(gpa: Gpa)`, `new_in(gpa)`,
  arenas, `FixedBuf`; effects are inferred per function and shown by
  `query effects`.

### 1.2 Spikes on today's compiler (2026-10-16, Apple M5, macOS 26.6.2)

Six small programs, compiled with this branch's `target/tools/tachyonc`
and linked with `cc ... -framework Metal -framework Foundation -lobjc`.
They are the evidence for §2.9; their code is in §3.1 and the appendix.

| # | spike | result |
|---|---|---|
| S1 | Metal **compute**: device, MSL compiled at run time, pipeline, shared buffer, `dispatchThreads:` with two `MTLSize` (24-byte structs passed indirectly), `waitUntilCompleted`, CPU check | 1024 floats correct, 0 mismatches; 166 ms cold (shader cache empty), **20 ms warm** for the whole process |
| S2 | Metal **render to texture**: render pipeline from MSL, 8×8 RGBA8 texture, `setClearColor:` (an HFA of four doubles in v0–v3), `getBytes:...fromRegion:` (a 48-byte `MTLRegion` by value), read back | exact pixel values (16,16,64,255) at (0,0) and (239,239,64,255) at (7,7) |
| S3 | an **Objective-C class defined at run time** (`objc_allocateClassPair`, `class_addMethod` with a tachyon `extern "C" fn` as the IMP, typed `class_addMethod` declaration) | `[o mul:6 by:7]` = 43 |
| S4 | a **block built by hand** (a global block: `isa = &_NSConcreteGlobalBlock`, `BLOCK_IS_GLOBAL`, a context field after the literal) given to `addCompletedHandler:` | the handler ran, **on a Metal thread, not the main thread** |
| S5 | **type encodings** read back: `protocol_getMethodDescription(objc_getProtocol("MTLDevice"), ...)` and `method_getTypeEncoding` | `@32@0:8Q16Q24` for `newBufferWithLength:options:`, `{?=QQQ}16@0:8` for `maxThreadsPerThreadgroup`: the runtime can check every binding |
| S6 | a **struct result** through `objc_msgSend` (`-> MTLSize`, x8 indirect) | 1024 × 1024 × 1024 |

S1 and S2 also ran under `MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1`
(API and GPU validation work without Xcode). A seventh spike imported
`CoreText/CoreText.h` through a directory of symlinks to the SDK's
framework `Headers` (16,218 lines of declarations in 0.17 s, 195 `CT`
functions) and rasterized a glyph; it belongs to 0.23 (terminal.md §1.2)
but proves the C importer reads Apple's C frameworks once it can find
them.

The host has the Command Line Tools only: no `metal` offline compiler,
no `xctrace`, no GPU frame capture. MSL is therefore compiled at run time
(as wgpu does), and the shader translator's output is checked by Metal
itself. `/usr/bin/leaks` and `footprint` are present.

### 1.3 The linux/arm64 container (probed 2026-10-16)

From the gate's image `tachyon-check:linux-aarch64` (Debian bookworm),
with `apt-get install`:

| package | version | gives |
|---|---|---|
| mesa-vulkan-drivers | 22.3.6 | **lavapipe**: Vulkan 1.3.230, `llvmpipe (LLVM 15.0.6, 128 bits)`, conformance 1.3.1.1; `VK_KHR_xcb_surface`, `xlib_surface`, `wayland_surface` |
| spirv-tools | 2023.1 | **spirv-val** for SPIR-V 1.0–1.6 and Vulkan 1.0–1.3 environments |
| vulkan-validationlayers | 1.3.239 | API and synchronization validation |
| libvulkan-dev, vulkan-tools | 1.3.239 | `vulkan_core.h` for the binding generator; `vulkaninfo` |
| spirv-cross, glslang-tools | 2021.01 / 12.0 | a second opinion on SPIR-V; GLSL references for tests |
| xvfb, weston | 21.1 / 10.0.1 | X11 and Wayland (headless backend) servers without a display: surfaces and swapchains are testable |
| libfreetype-dev, libfontconfig-dev | 2.12.1 / 2.14.1 | 0.23's Linux font path |

So everything on the Vulkan side, swapchains included, can be tested
without a GPU or a display. The gate gets a second image,
`tachyon-check:linux-aarch64-gpu`, with these packages; the minimal image
stays as it is.

### 1.4 Gaps to close

| # | gap | closed by |
|---|---|---|
| F1 | a library cannot say "link Metal" | `-framework NAME` and `-F DIR` as link inputs (C4); std's own bindings need neither (§2.8) |
| F2 | `import` cannot find framework headers | framework lookup in front/cpp (C4) |
| F3 | shaders are one-line strings | `include_str("file")` (C3) |
| F4 | Metal and AppKit have no C headers | typed bindings generated from a table and checked against the runtime (§2.9) |
| F5 | callbacks arrive on foreign threads | none before 0.21; until then, no callback may run off the main thread (§2.11) |
| F6 | a large library in std would slow every compile | std submodules loaded on use (C2) |
| F7 | one source, Metal on macOS and Vulkan on Linux | OS-specific module files (C1) |
| F8 | shader code can read out of bounds: undefined behaviour on the GPU | the translator inserts checks (§2.10) |

## 2. The model (decided)

### 2.1 Layers

```
std::gpu              the API: wgpu's objects, tachyon's shapes (§2.2–2.7)
  std::gpu::core      validation, lifetimes, tracking; generic over hal::Api
  std::gpu::hal       trait Api { type Device; type Buffer; ... }: the backend interface
  std::gpu::metal     hal for Metal          (gpu/metal.macos.tach + metal/)
  std::gpu::vk        hal for Vulkan         (gpu/vk.linux.tach + vk/)
  std::gpu::wgsl      the shader compiler: WGSL subset -> IR -> MSL | SPIR-V (§2.10)
std::objc             the Objective-C runtime: Id<T>, selectors, classes, blocks, pools (§2.9)
```

This is wgpu's split (wgpu, wgpu-core, wgpu-hal, naga), with two
differences. Dispatch is static: there is no `dyn`, and the hal is chosen
per OS at compile time (§2.8). Commands are encoded straight into the
native encoder when the call happens: there is no intermediate command
stream to replay, except where Vulkan needs one to place barriers
(§2.8).

### 2.2 The API: wgpu's objects

| wgpu | tachyon | kind (0.17) | notes |
|---|---|---|---|
| `Instance` | `gpu::Instance` | owned | holds the allocator (`Instance::new_in(gpa)`) |
| `Adapter` | `gpu::Adapter` | plain | a description plus a native handle; `inst.adapters()` lists, `inst.adapter(Power::High)` picks |
| `Device`, `Queue` | `gpu::Device`, `gpu::Queue` | owned | `adapter.device(limits)? -> (Device, Queue)` |
| `Buffer` | `gpu::Buffer` | owned | `dev.buffer(size, usage)`, `dev.buffer_init(bytes, usage)` |
| buffer mapping | `buf.map_read(&dev) -> Result<[u8]>`, `buf.map_write(...) -> &mut [u8]` | **view** of the buffer | the buffer cannot be used, submitted or dropped while the view lives: wgpu's run-time "buffer is mapped" check becomes a 0.17 compile error |
| `Texture`, `TextureView` | `gpu::Texture`, `gpu::TextureView` | owned | a view keeps its texture alive (§2.3) |
| `Sampler` | `gpu::Sampler` | owned | |
| `ShaderModule` | `gpu::Shader` | owned | `dev.shader(src)?`: WGSL translated here; errors are `ShaderError` with line, column and code |
| `BindGroupLayout`, `PipelineLayout` | `gpu::BindLayout`, `gpu::PipelineLayout` | owned | usually reflected from the shader: `pipe.bind_layout(0)` |
| `BindGroup` | `gpu::BindGroup` | owned | keeps its resources alive |
| `RenderPipeline`, `ComputePipeline` | same names | owned | descriptors with defaults (§3) |
| `CommandEncoder`, `CommandBuffer` | `gpu::Encoder`, `gpu::Commands` | owned | `enc.finish() -> Commands`, consumed by `queue.submit` |
| `RenderPass`, `ComputePass` | `gpu::RenderPass`, `gpu::ComputePass` | **view**, closure-scoped | `enc.render_pass(&desc, \|pass\| { ... })` |
| `Surface`, `SurfaceTexture` | `gpu::Surface`, `gpu::Frame` | owned; `Frame` is a view of the surface | `surf.frame()? -> Frame`, `frame.present(&queue)` consumes |
| errors | `gpu::Error` | plain enum | `Result` for what can fail at run time; contract failures for misuse (§2.6) |

Flags are 0.18's distinct types: `type BufferUsage = distinct u32` with
`|`, so `BufferUsage::VERTEX | TextureUsage::COPY_DST` is a type error.
Descriptors are small `#[derive(Clone)]` structs, and the constructors
take default parameter values (0.15), so a common call names only what
differs: `dev.texture(w, h, Format::Rgba8Unorm, usage = RENDER |
COPY_SRC)`.

### 2.3 Ownership and lifetimes

- **Resources are owned values with `Drop` (0.17).** Dropping one is
  always safe, even while the GPU still uses it. The device defers the
  native destruction until every submission that uses the resource has
  completed. Each submission has an index, and every resource records
  the last index that used it, as wgpu-core does.
- **What holds what.** A bind group, a texture view, a pipeline and a
  submitted command buffer keep their resources alive by an internal
  reference count. On Metal this is the object's own retain count; on
  Vulkan it is a count in the device's resource table. This happens when
  an object is created or bound, never per draw. An encoder records each
  bind group and pipeline once (a small set, deduplicated by id), and
  releases them when its submission completes. Metal command buffers are
  created with unretained references, so Metal does no retain of its own
  on each `set*`.
- **Mapped ranges are views** (0.17 §2.4). `map_read` is
  `#[views(self)]`: the slice points into the buffer, and the buffer is
  borrowed while it lives.
- **Passes are closure-scoped views.** A view type may not implement
  `Drop` (0.17 §2.2), so "end the pass when it goes out of scope" cannot
  be a destructor. `enc.render_pass(&desc, |pass| ...)` begins the pass,
  runs the closure with `pass: &mut RenderPass`, and ends it. The closure
  cannot keep the pass, and the encoder cannot be used inside it, because
  it is exclusively borrowed. That is wgpu's lifetime-parameterized
  `RenderPass<'a>`, with no lifetime written.
- **`Frame` is a view of its surface.** `frame.present(&queue)`
  consumes it; a frame that is dropped unpresented is a contract error
  (`gpu.frame_dropped`). A view type has no `Drop`, so the check runs at
  the next `surf.frame()` call.
- **The surface keeps its window's native objects alive** by reference
  count: the `CAMetalLayer` is retained; on Wayland and X11, the
  window library's surface record is counted. A `Surface` may outlive its
  `Window`, and presenting then does nothing.
- **Before 0.17** the same types exist with `free(self: *T)` and
  `defer x.free()`. `fix --values` deletes the defers once `Drop` lands
  (§6.4). Passes are already closures today.

### 2.4 Allocation (0.16)

- **Host memory comes from the instance's allocator**, and the device and
  its children inherit it: descriptor tables, the resource table,
  pipeline caches, Vulkan's recorded passes.
- **The per-frame host memory is one arena per frame in flight,** reset
  when that frame's submission completes. It holds recorded Vulkan
  passes, barrier lists and temporary descriptor writes. After warm-up,
  steady-state frames allocate nothing from `Gpa`. This is checked:
  `query effects --has alloc(Gpa) app::frame` must print nothing, and
  examples/gpu's frame functions declare `#[effects(io, panic,
  alloc(Arena))]`.
- **GPU memory is not host memory,** and does not go through the
  `Allocator` trait. The Vulkan hal has its own sub-allocator in tachyon:
  64 MiB blocks per memory type, a TLSF free list inside each, and
  dedicated allocations above 32 MiB or when the driver prefers them.
  Metal allocates each resource from the device, which sub-allocates
  itself. `MTLHeap` waits for evidence that it helps (O3).

### 2.5 Effects (0.16)

- **What touches the device is `io`.** The extern declarations of both
  hals are `#[effects(io)]` (trusted, as C declarations are), and
  allocation in the drivers is `alloc(extern)`. 0.22 adds no new effect
  kind.
- **What does not touch the device is proven not to.**
  - The WGSL compiler is `#[effects(alloc(Arena), panic)]`: no `io`, no
    `global`, so a shader can be translated anywhere, for instance on a
    worker thread in 0.21.
  - The validation helpers are `#[pure]`.
  - The reflection of a shader into bind layouts is pure.
- `query effects std::gpu` shows the split, and `guide gpu` uses it to
  explain where the cost is.

### 2.6 Validation as contracts (0.18)

wgpu-core is mostly validation. Here it is a set of `requires` clauses on
the public functions, each naming a rule. They are checked at run time;
a violation exits with 101 and prints the rule's code, its text and the
call site. The optimizer removes a check only where range analysis
proves it, never by assuming it (0.18).

| code | rule (abridged) | where |
|---|---|---|
| `gpu.usage` | a buffer bound as vertex, index, uniform or storage, or used in a copy, was created with that usage | `set_vertex_buffer`, `copy_*`, `bind_group` |
| `gpu.align` | uniform and storage offsets are multiples of the device's alignment (256 on Metal and on lavapipe); copy offsets and sizes are multiples of 4 | the same |
| `gpu.range` | `offset + size <= buffer.size`; a draw's vertex and instance ranges are within the bound vertex buffers (with their strides) | `set_*`, `draw`, `draw_indexed` |
| `gpu.layout` | a bind group matches its layout: every binding present, of the right kind, format and access | `bind_group`, `set_bind_group` |
| `gpu.pipeline` | a draw or dispatch has a pipeline, and every group its layout needs is bound | `draw*`, `dispatch*` |
| `gpu.format` | render target formats match the pipeline's; the format is renderable, filterable or storable as used | pass begin, pipeline creation |
| `gpu.limits` | sizes, counts and workgroup dimensions are within the device's limits | creation, `dispatch` |
| `gpu.frame_dropped` | a frame from `surf.frame()` is presented before the next | `Surface::frame` |

- **What is checked statically instead.**
  - A mapped buffer in use, a pass outliving its encoder, and an encoder
    used during its pass are 0.17 errors (§2.3).
  - A `BufferUsage` passed as a `TextureUsage` is a type error (distinct
    types, 0.18).
- **What is not validated on the CPU.** wgpu does not validate index
  buffer contents either. Here an out-of-range index cannot cause
  undefined behaviour, because the shader translator bounds-checks every
  access the shader makes (§2.10).
- **Cost.** These are integer comparisons on values the call already
  loads: a few nanoseconds per call against roughly 100 ns per native
  call. The bench gate (§5) measures them.
- **Before 0.18** each public function starts with
  `validate(cond, Rule::Usage)` statements in that exact form. A small
  refactor script turns the leading `validate` lines into `requires`
  clauses (§6.4).

### 2.7 Errors

- **`Result<T, gpu::Error>`** for what can fail however correct the
  program is: no adapter, out of device memory, a shader the translator
  rejects (`Error::Shader(ShaderError)`), a pipeline the driver rejects,
  device lost, surface outdated or lost.
- **A contract failure** for misuse (§2.6).
- **No error scopes and no uncaptured-error callbacks**, which wgpu
  needs because its validation is deferred. Here every check happens at
  the call.
- `ShaderError` prints in the compiler's one-line form,
  `cells.wgsl:12:5: error wgsl.type: cannot add 'vec3<f32>' and 'f32'`,
  followed by a `help:` line (§2.13).

### 2.8 Backends

**Selection: OS-specific module files (C1).** `mod native;` loads
`native.macos.tach` on macOS targets and `native.linux.tach` on Linux
targets (else `native.tach`). Every variant is **type-checked on every
host**, and only the target's is generated, so an agent on the Mac who
breaks the Vulkan hal sees the error at `tachyonc check`. This is 0.19's
rule for foreign architectures ("checked, never generated") applied to
files. It needs no `cfg` syntax, it is Go's well-known `_linux.go`
convention, and both hals implement `trait hal::Api`, so their interfaces
cannot drift. std's hal modules declare their C functions by hand or
generated from tables (§2.9), never by `import`, so the foreign variant
needs no foreign headers.

**Metal (first).**
- **Objects.** `MTLCreateSystemDefaultDevice` (or `MTLCopyAllDevices`
  for `adapters()`), one `MTLCommandQueue` per `Queue`. Buffers use
  `MTLResourceStorageModeShared` on Apple silicon (unified memory: a
  mapped range is the buffer's `contents`, with no staging) and
  `Private` for textures that are only rendered and sampled.
- **Binding.** The translator assigns Metal slots per stage:
  `[[buffer(n)]]`, `[[texture(n)]]`, `[[sampler(n)]]`. Its reflection
  table maps (group, binding) to slots, and `set_bind_group` issues the
  `setVertexBuffer:`/`setFragmentBuffer:`/`setBuffer:` calls for the
  group's entries. Vertex buffers take slots from 30 downward. A hidden
  sizes buffer (`setBytes:` at the last slot) carries runtime array
  lengths for bounds checks. Argument buffers are a later optimization
  (O2).
- **Synchronization.** Hazards between passes are tracked by Metal for
  tracked resources. That is the default here, and untracked resources
  are a later optimization. Before 0.21 the CPU waits by
  `waitUntilCompleted`, or polls `MTLSharedEvent.signaledValue` at frame
  start, never by a completion handler (§2.11). Frames in flight: three,
  each with its own instance-data buffer slot.
- **Presentation.** `CAMetalLayer.nextDrawable`, `presentDrawable:` on
  the command buffer. `maximumDrawableCount = 2` and
  `displaySyncEnabled` are surface options: the terminal wants the
  lowest latency.

**Vulkan (second).**
- **The loader and the bindings.** `libvulkan.so.1` is opened with
  `dlopen`, and instance and device function pointers are loaded into a
  table (volk's model). Device-level calls go through
  `vkGetDeviceProcAddr` pointers, which skip the loader's trampoline. The
  bindings are generated once by `tachyonc --emit-imports` from
  `vulkan_core.h` 1.3.239 in the container and checked in
  (`gpu/vk/sys.tach`), so building needs no Vulkan headers anywhere.
- **The version.** Vulkan 1.3 is required, which lavapipe and every
  current desktop driver provide. That gives dynamic rendering (no
  `VkRenderPass`/`VkFramebuffer` objects), synchronization2 and timeline
  semaphores (one per queue, so a submission index is a semaphore
  value).
- **Barriers.** A pass's commands are recorded into the frame arena as a
  compact list while the pass runs. At the pass's end, the hal computes
  the transitions its resources need (layouts, access masks), emits one
  `vkCmdPipelineBarrier2`, then replays the list into the command buffer.
  This is the one place commands are not encoded immediately: Vulkan
  barriers cannot go inside a rendering instance, and the pass's
  resources are known only at its end. Compute passes replay the same
  way.
- **Descriptors.** One `VkDescriptorSetLayout` per bind layout. Bind
  groups allocate sets from a growing list of pools. Push descriptors
  wait for evidence (O2).
- **Presentation.** `VK_KHR_swapchain` on the window library's
  `VkSurfaceKHR` (`wayland_surface`, `xcb_surface`): FIFO by default,
  MAILBOX when asked for and available.

### 2.9 Calling Objective-C from tachyon (`std::objc`)

The spikes (§1.2) show the mechanics work today. The design is about
making them safe to write in volume: Metal alone needs about 150
selectors, and AppKit in 0.23 about 120.

- **One typed declaration per selector shape.**
  `#[link_name = "objc_msgSend"] fn msg_p_u_u(o: *u8, s: *u8, a: *u8, b:
  u64, c: u64) -> *u8;` and so on. Shapes are shared by selectors with
  the same C types. arm64 has no `objc_msgSend_stret` and no `_fpret`:
  struct results use x8 and float results v0, as for any C call (S2,
  S6). The x86_64 variants are out of scope (no x86 work).
- **A binding table, a generator and a runtime check.**
  - The bindings are written as a table, `compiler/std/objc/tables/*.objc`:

    ```
    protocol MTLDevice
      newBufferWithLength:options:  (length: u64, options: u64) -> own MTLBuffer?
      maxThreadsPerThreadgroup      () -> MTLSize
      name                          () -> NSString
    ```

  - `tools/objcgen`, a tachyon program, turns the table into
    `metal/sys.tach`, which is checked in. It emits the typed shapes, one
    small `unsafe fn` per selector, and the selector cache.
  - The generator **checks every line against the runtime's own
    metadata** on the Mac: `protocol_getMethodDescription` for protocols,
    `class_getInstanceMethod` for classes (S5). A table line whose C
    types disagree with the runtime's type encoding (`@32@0:8Q16Q24`) is
    an error at generation time, with the encoding in the message.
  - A test regenerates the file and diffs it against the checked-in one.
  - Under `--check-unsafe` each wrapper also checks its receiver's
    encoding at its first call. That catches a protocol implemented by a
    class that differs.
  - This is the answer to the largest risk of the release (§8, R1): a
    wrong prototype is silent memory corruption, so no prototype is
    written by hand.
- **Ownership: `Id<T>`.** It is an owned handle (0.17) to an
  Objective-C object of class or protocol `T`. `T` is a zero-sized marker
  type, so `Id<MTLBuffer>` and `Id<MTLTexture>` do not mix.
  - `Drop` sends `release` and `Clone` sends `retain`.
  - The table's `own` marks the +1 results (Cocoa's `new`, `alloc`,
    `copy` and `mutableCopy` families), which become `Id<T>`.
  - Other object results are +0 and come back as `Ref<T>`, a view of the
    current autorelease pool. `.retain()` turns one into an `Id<T>`.
  - `?` in the table marks a nullable result, which becomes
    `Option<Id<T>>`.
  - Before 0.17, `Id<T>` has `free(self: *Id<T>)`, which sends
    `release`, and code writes `defer x.free()`. It is named `free` on
    purpose, so that `fix --values` migrates it as it migrates `Vec`
    (§6.4).
- **Selectors are cached in statics.** The cache is filled on first use
  by `sel_registerName`: one load and one predictable branch per call.
  Emitting `__objc_selrefs` sections, so that dyld fixes them up at load
  as clang does, saves that branch. It waits for a measurement that shows
  it matters (O1).
- **Autorelease pools:** `objc::pool(|| { ... })`, a closure-scoped push
  and pop. The window library wraps each event and each frame in one.
- **Classes defined in tachyon** (needed by 0.23: an `NSView` subclass,
  a window delegate, an `NSTextInputClient`):
  `objc::ClassBuilder::new("TachyonView", superclass)`, `.method(sel,
  imp, "v@:@")`, `.ivar("state", 8)`, `.protocol(...)`, `.register()`.
  - IMPs are `extern "C" fn`s whose first two parameters are
    `this: *u8, cmd: *u8` (S3).
  - The instance's Rust-side state is a raw pointer stored in an ivar,
    reached by `unsafe` code inside std only.
  - `class_addMethod` is declared once per IMP shape, because
    `extern "C" fn` types do not cast to `*u8`.
- **Blocks.** `objc::Block<F>` lays out a block literal by hand (S4):
  - a global block (`_NSConcreteGlobalBlock`, `BLOCK_IS_GLOBAL`), so the
    runtime's `Block_copy` returns it unchanged;
  - a context pointer after the descriptor, which the invoke function
    reads.

  Its memory is owned by the tachyon side and freed when the API
  guarantees the block is no longer called. Until 0.21, std passes blocks
  only to APIs that call them on the calling thread. Metal's completion
  handlers do not (S4), so they are not used (§2.11).
- **Exceptions.** An Objective-C exception that reaches tachyon frames
  terminates the process: no tachyon frame has a personality routine, so
  no handler is ever found and the runtime calls `std::terminate`. That
  is a crash, not undefined behaviour. Phase 0 confirms it with a test
  that throws through a tachyon frame.
  The contracts (§2.6) run first, so a well-typed call that passes them
  should not throw. `objc::init` installs `NSSetUncaughtExceptionHandler`
  to print the exception's name and reason before the abort.
- **`std::objc` is public.** Programs that call other Apple APIs use the
  same `Id<T>`, `ClassBuilder`, `pool` and `objcgen` table format. `guide
  objc` documents it, with the S1 compute program as its example.

### 2.10 Shaders: a WGSL subset compiled in tachyon (`std::gpu::wgsl`)

**Pipeline.** The pipeline is naga's, kept small:

```
source -> lexer -> parser (AST) -> resolver + type checker (abstract numerics, overloads)
       -> IR (typed expression arenas per function, structured statements)
       -> validator (layout, uniformity, entry-point interface)
       -> bounds-check insertion -> MSL writer | SPIR-V writer | interpreter (tests)
       -> reflection (bind groups, vertex inputs, workgroup size)
```

Everything runs on one arena per translation, with `alloc(Arena)` only.
The IR is plain data (`i64` handles into `Vec`s), so the start-now code
and the 0.17 code are the same.

**The subset (0.22.0).**

| in | later |
|---|---|
| `bool i32 u32 f32`; `vecN<T>`, `matCxR<f32>`; fixed and runtime-sized arrays; structs; `atomic<i32/u32>` | `f16`, `override` constants, `alias` |
| address spaces `function private workgroup uniform storage(read, read_write)` | pointers as function parameters beyond `ptr<function, T>` |
| `texture_2d<f32/i32/u32>`, `texture_depth_2d`, `texture_storage_2d<F, write>`, `texture_2d_array<f32>`, `sampler`, `sampler_comparison` | cube, 3D and multisampled textures; `texture_external` |
| `@vertex @fragment @compute @workgroup_size`; `@builtin @location @group @binding @interpolate(flat)` | `@invariant`, `@blend_src`, subgroups |
| `let var const`, `if switch loop for while break continue return discard`, compound assignment, `++ --` | `const_assert`, `diagnostic`, `enable` directives |
| the math, vector, matrix, packing and texture builtins, `select`, `arrayLength`, `atomic*`, `workgroupBarrier`, `storageBarrier`, `dpdx/dpdy/fwidth` | `textureGather`, `textureSampleGrad` (0.22.x) |

The subset is chosen from the shaders 0.22's tests and examples need,
the terminal's cell shader, and wgpu's example shaders that fit. Each
feature is accepted only once all three outputs implement it.

**Semantics with no undefined behaviour.** WGSL defines more than MSL
does, and the translator keeps WGSL's definitions:
- integer `/` and `%` by zero, and `MIN / -1`, follow WGSL's rules
  through helper functions, as naga's do;
- **every index is checked**:
  - fixed arrays, vectors and matrices are clamped (naga's `Restrict`);
  - runtime-sized storage arrays read zero and skip writes out of range
    (`ReadZeroSkipWrite`). The length comes from `OpArrayLength` in
    SPIR-V, and from the hidden sizes buffer in MSL;
  - `textureLoad` and `textureStore` coordinates are checked against
    `textureDimensions`;
- a check is dropped only where a dominating comparison proves the index
  in range (`if i < arrayLength(&a) { a[i] }`, `for (var i = 0u; i <
  N; i++)` over `array<T, N>`). The rule is 0.18's, applied inside
  shaders. The bench measures the cost.

**The outputs.**
- **MSL 3.0** (macOS 14 or later, the platform floor of 0.22–0.23). It
  is text, compiled by `newLibraryWithSource:` at pipeline creation.
- **SPIR-V 1.3**, validated with `spirv-val --target-env vulkan1.3` in
  the tests. It has structured control flow (`OpSelectionMerge`,
  `OpLoopMerge`), `Block` and `Offset` decorations from WGSL's layout
  rules, and `OpEntryPoint` interfaces.
- **The interpreter**, a third back end over the same IR, written in
  tachyon. It runs compute entry points and single fragment invocations
  on the CPU and is the oracle for the tests (§4).

**Diagnostics** use the compiler's form: `file:line:col: error
wgsl.CODE: message`, with `help:` lines; `tachyonc explain wgsl.CODE`
explains each code. The uniformity analysis follows the WGSL
specification and reports the non-uniform value's origin, as naga does.

**Performance.** Translating is under 1 ms for the terminal's shader and
under 10 ms for the largest shader of the corpus, compared with naga in
the bench. Metal's own MSL compile, 10–40 ms cold, dominates the first
pipeline. The OS keeps it in its shader cache (S1: 166 ms cold, 20 ms
warm for the whole process). A `PipelineCache` that keeps Metal binary
archives or `VkPipelineCache` data on disk is in 0.22.0, because the
terminal's start-up time counts.

**Where it runs.** At run time, in `dev.shader(src)`, as wgpu does.
Sources come from `include_str("cells.wgsl")` (C3), so they live in
`.wgsl` files and are embedded at compile time. Checking shaders during
`tachyonc check` needs the translator inside compiler/src. The release
rule allows that from 0.23 at the earliest, and it is O4.

### 2.11 Threads (0.21)

- **Before 0.21 nothing runs off the main thread.** Metal's completion
  and scheduled handlers, `CVDisplayLink` and `dispatch_async` all call
  back on threads tachyon does not know about (S4), and tachyon's statics
  are only safe because there is one thread. std::gpu does not use them:
  it waits with `waitUntilCompleted` or polls shared-event values.
- **With 0.21:**
  - `Device`, `Queue`, the resources and `BindGroup` are `Sync`
    (inferred from their fields and declared through the hal);
  - `Encoder` is `Send` but not `Sync`;
  - completion callbacks become `queue.on_done(index, closure)` with
    owned (`move`) closures, called on a std-managed thread;
  - encoders may be recorded on several threads and submitted in order.

  The resource table and descriptor pools take a lock; the frame arenas
  are per encoder.

### 2.12 Alternatives considered

- **Bind wgpu-native (its C API) and naga as a C library.** It is the
  fastest way to pixels, but it misses the release's purpose: the API
  would be wgpu's (no `Drop` on resources, no views, run-time checks of
  what 0.17 proves), the shader compiler would not dogfood tachyon, and a
  Rust toolchain would become a dependency of std. Rejected. wgpu and
  naga remain the reference for behaviour and the bench's baseline.
- **Port naga line by line.** Its IR is good and is the model, but it is
  45k lines of Rust built on lifetimes, `Arena<T>` handles and `Result`
  chains. A tachyon design of a third that size, covering the subset,
  costs less than a port and reads better.
- **GLSL instead of WGSL.** WGSL has a specification, a defined
  uniformity analysis and defined out-of-bounds behaviour, and agents
  know it from wgpu. GLSL has none of these. Kept WGSL.
- **MoltenVK only (one Vulkan backend everywhere).** It is one hal
  instead of two, but it is a translation layer over Metal, with its own
  bugs and a C++ dependency, and Metal is the main platform. Rejected.
  MoltenVK may still be used to smoke-test the Vulkan hal on a Mac, by
  hand (O5).
- **An Objective-C front end in the C importer**, parsing `@interface`
  and `@protocol` from Apple's headers. It is the most complete source of
  prototypes, but Objective-C syntax in front/cpp and front/cimport is a
  large addition to the compiler, and the table plus runtime check (§2.9)
  covers what std needs. Rejected for 0.22, and possible later if users
  ask for broad Apple API access (O6).
- **Run-time backend dispatch** (an enum over backends, libraries opened
  with `dlopen`). One binary would hold both hals and could fall back to
  lavapipe. The cost is calls through function pointers, effects that
  cannot be trusted per declaration, and dead code on every platform.
  OS-specific files are simpler and static. Vulkan still opens
  `libvulkan` with `dlopen`, because its loader expects that.
- **Recording every command and replaying it** (wgpu-core). It would
  make the backends uniform, but it costs a copy of every command. Kept
  only where Vulkan barriers need it (§2.8).

### 2.13 What agents see

- **`tachyonc guide gpu`**: the objects in one table (§2.2), the
  compute example of §3.2 and the render example of §3.3, both run by
  tests/guide; and the six commonest failures with their fixes:
  1. `gpu.usage` → add the usage at creation;
  2. `gpu.align` → round the offset with `dev.align_uniform(n)`;
  3. `gpu.layout` → the binding the shader declares;
  4. `wgsl.type` → the cast;
  5. `wgsl.uniformity` → move the `textureSample` out of the branch;
  6. a 0.17 error for a mapped buffer still in use → end the view first.
- **`tachyonc explain gpu.usage`** (and every `gpu.*` and `wgsl.*` code):
  the rule, an example, the fix.
- **Contract failures** print the rule and the `try:`:
  `contract gpu.usage failed: buffer 'verts' (usage COPY_DST) bound as
  VERTEX at main.tach:41:9`, then `try: create it with usage = VERTEX |
  COPY_DST (main.tach:22)`.
- **Shader errors** carry the `.wgsl` file's own line and column, even
  through `include_str`: the compiler records the included file's name
  with the constant.
- **`query effects`** shows `io` on every device call (§2.5), and `query
  show std::gpu::Device::buffer` shows the contracts once 0.18 is in.
- **No `unsafe` in user code for GPU work**, on either backend. The
  `unsafe` is in std::objc, the hals and the generated bindings.

## 3. Examples

### 3.1 Today (start-now form, a spike)

The S1 compute spike, abridged. This is the level std::objc and the
Metal hal build on, and no user writes it:

```tach
#[repr(C)] struct MTLSize { w: u64, h: u64, d: u64 }
extern "C" {
    fn MTLCreateSystemDefaultDevice() -> *u8;
    fn sel_registerName(name: *u8) -> *u8;
    #[link_name = "objc_msgSend"] fn msg(o: *u8, s: *u8) -> *u8;
    #[link_name = "objc_msgSend"] fn msg_buf(o: *u8, s: *u8, len: u64, opts: u64) -> *u8;
    #[link_name = "objc_msgSend"] fn msg_dispatch(o: *u8, s: *u8, grid: MTLSize, tg: MTLSize);
    // ...
}
// ...
let buf = msg_buf(dev, sel(c"newBufferWithLength:options:"), n * 4, 0);
let p = msg(buf, sel(c"contents")) as *f32;
// ...
msg_dispatch(enc, sel(c"dispatchThreads:threadsPerThreadgroup:"),
             MTLSize { w: n, h: 1, d: 1 }, MTLSize { w: tw, h: 1, d: 1 });
```

### 3.2 Compute, as 0.22 writes it (0.17 and 0.18 in)

```tach
use std::gpu::{self, BufferUsage};

fn main(gpa: Gpa) -> Result<(), gpu::Error> {
    let inst = gpu::Instance::new_in(gpa);
    let (dev, queue) = inst.adapter(gpu::Power::High)?.device()?;
    let shader = dev.shader(include_str("saxpy.wgsl"))?;
    let pipe = dev.compute_pipeline(&shader, "main")?;

    let n = 1 << 20;
    let xs = dev.buffer_init(as_bytes(&make_input(n, gpa)), BufferUsage::STORAGE | BufferUsage::COPY_SRC);
    let out = dev.buffer(n * 4, BufferUsage::MAP_READ | BufferUsage::COPY_DST);
    let group = dev.bind_group(&pipe.bind_layout(0), &[gpu::bind(0, &xs)]);

    let mut enc = dev.encoder();
    enc.compute_pass(|pass| {
        pass.set_pipeline(&pipe);
        pass.set_bind_group(0, &group);
        pass.dispatch((n + 255) / 256, 1, 1);
    });
    enc.copy_buffer(&xs, 0, &out, 0, n * 4);
    queue.submit(enc.finish());

    let bytes = out.map_read(&dev)?;          // a view of `out`: waits for the submission
    println(f"{as_f32s(bytes)[3]}");
    Ok(())                                     // everything dropped, in reverse order
}
```

`saxpy.wgsl` has `@group(0) @binding(0) var<storage, read_write> xs:
array<f32>;` and `@compute @workgroup_size(256)`. The bind layout comes
from the shader.

### 3.3 Render to a texture, read back (the headless test's shape)

```tach
let tex = dev.texture(64, 64, gpu::Format::Rgba8Unorm, usage = gpu::TextureUsage::RENDER | gpu::TextureUsage::COPY_SRC);
let pipe = dev.render_pipeline(&gpu::RenderDesc::new(&shader, "vs", "fs", tex.format()))?;
let mut enc = dev.encoder();
enc.render_pass(&gpu::PassDesc::color(&tex.view(), clear = gpu::Color::BLACK), |pass| {
    pass.set_pipeline(&pipe);
    pass.draw(0..3, 0..1);
});
let rb = dev.buffer(64 * 64 * 4, gpu::BufferUsage::MAP_READ | gpu::BufferUsage::COPY_DST);
enc.copy_texture_to_buffer(&tex, &rb, bytes_per_row = 256);
queue.submit(enc.finish());
let pixels = rb.map_read(&dev)?;
check_image(pixels, "tests/gpu/ref/triangle.ppm", tolerance = 1);
```

## 4. Testing

**What runs where.**

| what | Mac, headless (no window) | Mac with a display | container (linux/arm64) |
|---|---|---|---|
| std::objc: classes, blocks, pools, `Id` retain counts (`retainCount` after each step), selector cache | yes | | the foreign variant type-checks |
| objcgen's runtime check of every table line | yes | | |
| Metal hal: compute, render to texture, copies, readback, every format the tests use, under `MTL_DEBUG_LAYER=1 MTL_SHADER_VALIDATION=1` | yes | | |
| Metal presentation (`CAMetalLayer`, drawables) | an unattached layer's `nextDrawable` only (to confirm in Phase 0) | yes: examples/gpu/triangle-window | |
| Vulkan hal: compute, render to texture, readback, with validation layers including synchronization validation | | | yes, lavapipe |
| Vulkan swapchain on X11 and Wayland | | | yes: Xvfb and `weston --backend=headless` |
| WGSL front end, IR, interpreter, golden MSL and SPIR-V | yes | | yes |
| MSL compiled by Metal | yes (`newLibraryWithSource:`) | | |
| SPIR-V validated | | | yes (`spirv-val --target-env vulkan1.3`) |
| the shader fuzzer, differential | interpreter vs Metal | | interpreter vs lavapipe |
| leaks of Objective-C objects | `leaks --atExit -- prog` | | |

**How images are compared.** The test scenes are designed to be exact:
axis-aligned rectangles on pixel centres and flat colours, so Apple's GPU
and lavapipe agree bit for bit. A few scenes with edges and blending
compare with a per-channel tolerance and a count of differing pixels.
References are PPM files under `tests/gpu/ref/`, written by the
interpreter-backed CPU rasterizer of the test harness, never by the GPU
under test.

**The shader fuzzer** (G7). It generates random well-typed WGSL compute
programs, in the manner of tests/fuzz for tachyon itself: integer
arithmetic, control flow, arrays, workgroup memory and atomics, with a
`@group(0)` buffer of results. Each program runs on the interpreter and
on the backend, and the outputs must agree. Floats are compared with a
ULP tolerance, or kept out of a mode. A failure is reduced by deleting
statements while it still fails. The gate runs it for 60 s in each mode
on each platform.

**The runner.** `tests/gpu/run.sh` follows tests/abi/run.sh, with
directives `// NEEDS: metal|vulkan|display` and `// IMAGE: ref.ppm
TOL`. A case whose need is missing is reported as skipped, never passed.
Gate rows:
- `gpu-metal` on the Mac;
- `gpu-vulkan` in the gpu image (lavapipe, spirv-val, Xvfb and weston);
- `wgsl` (golden outputs and the interpreter) on both;
- `gpu-fuzz` on both.

The display rows are run by hand, before a release only, and recorded in
docs/releases.md (§7).

## 5. Performance

Performance is the first requirement after correctness. Every number
below is a bench in `bench/gpu/`, run by `gate.sh --only bench`, with the
baseline built from the same source each time.

| measure | baseline | goal |
|---|---|---|
| CPU cost of encoding 10,000 draws with a bind group change every 10 | the same in Objective-C with clang -O2 (`bench/gpu/draws.m`), and in wgpu (Rust, pinned) | within 10% of Objective-C; faster than wgpu |
| CPU cost of `queue.submit` plus frame acquire and present, idle scene | Objective-C | within 5% |
| validation overhead (§2.6) | `--gpu-contracts=off`, a bench-only build flag that is never shipped | under 3% of encoding cost |
| shader bounds checks (§2.10) | the same kernels translated unchecked (bench-only) | under 5% on bench kernels: saxpy, a 1M-element reduction, a 4k² image blur |
| WGSL → MSL and → SPIR-V translation | naga-cli (pinned) on the same corpus | no slower than naga |
| compile time of a program that does not use std::gpu | 0.21 | unchanged (std submodules load on use, C2) |
| compile time of examples/gpu | | reported each release |

## 6. Phase 0, then the tasks

### 6.1 Dependencies

| needs | from | parts that wait |
|---|---|---|
| `Drop`, moves, `&T`/`&mut T`, views, `#[views]` | 0.17 | the final shape of every resource type (`free` → `Drop`), passes' `&mut RenderPass`, mapped ranges as views, `Frame` as a view, `Ref<T>` as a view of the pool. The code is written now in the 0.16 form and migrated (§6.4) |
| contracts (`requires`), distinct types | 0.18 | §2.6's rules as `requires` (written now as `validate` statements); `BufferUsage` and friends as distinct types (now `u32` constants) |
| `has("macos")` or other OS facts | 0.19/0.20 | nothing: C1's OS-specific files cover the backend choice |
| text, `HashMap` rework, files | 0.20 | nothing essential; WGSL sources are `[u8]` and `include_str` |
| threads, atomics, `Send`/`Sync` | 0.21 | §2.11: completion callbacks, multi-threaded encoding, the `Sync` declarations. Everything else is single-threaded by design |

**Nearly all of 0.22 can start now.** The compiler enablers (C1–C4), the
Objective-C layer, both hals, the whole shader compiler, the interpreter
and fuzzer, the tests and benches, and the core in its 0.16 form need
nothing from 0.17–0.21. What waits is migration work, plus the threading
items.

**Where start-now code lives.** At its final path from the first commit:
compiler/std/objc/, compiler/std/gpu/. C2 lets programs and tests load
`std::NAME` from `compiler/std/NAME/` on disk with `--std-dir DIR`. A
std module joins the embedded std (embed.sh's manifest) only when its
release ships, so 0.17–0.21 do not ship half a GPU library.

### 6.2 Phase 0: the interface commits (start now; the lead, serial)

**C. Compiler enablers** (small; compiler/src on 0.16's language; each
with tests, guide and explain entries):

| # | what | files |
|---|---|---|
| C1 | OS-specific module files: `mod m;` loads `m.macos.tach`, `m.linux.tach` or `m.tach` for the target; every variant type-checked, the target's generated; `query`/`refactor` see all variants | front/modules/lookup.tach, the module loader, tools' file walk; tests/run/os_files_* |
| C2 | std submodules: `std::objc`, `std::gpu` and later `std::window` loaded only when a program names them (sections inside, as std's); `--std-dir DIR` loads them from disk; embed.sh's manifest lists the shipped ones | front/modules/stdsections.tach, front/stdsrc.tach, compiler/std/embed.sh, main.tach |
| C3 | `include_str("path")`: a `[u8]` constant of a file relative to the source file, recorded for the query cache's dependencies and for diagnostics that point into it | front/check (a builtin), front/stdsrc or a new front/include.tach, the cache's dependency list |
| C4 | `-framework NAME` and `-F DIR` link inputs; framework lookup in `import` (`X/Y.h` → `DIR/X.framework/Headers/Y.h`, the SDK's `System/Library/Frameworks` by default, umbrella sub-frameworks); the tools accept `-I` and `-F` | main.tach, back/objfile/output.tach, front/cpp/directives.tach (`find_include`), tools' option parsing (`fix` and `edit` reject `-I` today) |

**I. Interfaces** (stubs; after them every task builds against fixed
signatures):

| file | contents |
|---|---|
| `compiler/std/objc/mod.tach` | `Id<T>`, `Ref<T>`, `Sel`, `pool`, `ClassBuilder`, `Block` signatures; the four spike shapes working |
| `compiler/std/objc/tables/README.md` | the `.objc` table format |
| `compiler/std/gpu/mod.tach` | the public types of §2.2 with their method signatures in the 0.16 form (`self: *T`, `free`), returning stubs |
| `compiler/std/gpu/hal.tach` | `trait Api` with its associated types and the hal operations (create, bind, encode, submit, wait, present) |
| `compiler/std/gpu/wgsl/ir.tach` | the IR: types, expressions, statements, functions, entry points, globals, handles; printing |
| `compiler/std/gpu/wgsl/mod.tach` | `pub fn translate(src: [u8], target: Target, arena: Arena) -> Result<Output, ShaderError>`, `Output { text_or_words, reflection }`, `Reflection` |
| `compiler/std/gpu/rules.tach` | the rule codes of §2.6 and `validate(cond, rule)` |
| `tests/gpu/run.sh` | the runner, its directives, one passing case per backend |
| `bootstrap/ci/linux-aarch64-gpu.Dockerfile` | the gpu image (§1.3) |

### 6.3 Then, in parallel

Every task below is **start now** unless marked.

| task | owns | provides | start |
|---|---|---|---|
| **G1 Objective-C layer** | compiler/std/objc/*, tools/objcgen/ | `Id<T>`, `Ref<T>`, selector cache, pools, `ClassBuilder`, `Block`, NSString/NSError helpers; objcgen with the runtime check (§2.9); `guide objc` draft | now |
| **G2 Metal hal** | compiler/std/gpu/metal.macos.tach, gpu/metal/*, objc/tables/metal.objc | §2.8's Metal column; tested at first with hand-written MSL, then with G5's | now (needs G1's `Id`; until then the spike's raw shapes) |
| **G3 Vulkan hal** | compiler/std/gpu/vk.linux.tach, gpu/vk/* (sys.tach generated), the gpu image | §2.8's Vulkan column; the sub-allocator; barriers by recorded pass; swapchain on Xvfb and weston | now (container) |
| **G4 WGSL front end** | gpu/wgsl/{lex,parse,ast,resolve,types,layout,uniformity,validate}.tach | the subset (§2.10) to IR; diagnostics and `explain wgsl.*`; the bounds-check pass | now |
| **G5 MSL writer** | gpu/wgsl/msl.tach | MSL 3.0 text, slots and reflection; tests by Metal compilation | now, after Phase 0's IR |
| **G6 SPIR-V writer** | gpu/wgsl/spirv.tach | SPIR-V 1.3 words; spirv-val clean | now, after Phase 0's IR |
| **G7 Interpreter and shader fuzzer** | gpu/wgsl/interp.tach, tests/gpu/fuzz/* | the oracle; the differential fuzzer against Metal and lavapipe; the CPU reference rasterizer for reference images | now, after Phase 0's IR |
| **G8 Core and API** | gpu/mod.tach, gpu/core/* | §2.2–2.7: lifetimes, submission tracking, deferred destruction, frame arenas, validation, errors, reflection-driven layouts; surfaces through `RawSurface` | now in the 0.16 form; final shape needs 0.17 and 0.18 (§6.4) |
| **G9 Tests, benches, guide, examples** | tests/gpu/*, bench/gpu/*, compiler/guide/gpu.md, examples/gpu/{compute,triangle,image-blur,triangle-window}, docs | the gate rows, the bench pairs (Objective-C, wgpu, naga), the guide topic and its six failures, the `explain gpu.*` entries | now; the guide's final text after 0.18 |

**Where the tasks meet.**
- **G4, G5, G6 and G7** meet at `wgsl/ir.tach`, which Phase 0 fixes.
  - A change to the IR is the lead's commit, with every consumer updated
    in it.
  - The bounds-check pass (G4) rewrites IR, so the writers never see an
    unchecked access.
- **G2 and G3** meet at `hal.tach`, through G8.
  - G8 owns the trait.
  - A hal that needs a new operation asks the lead. The other hal gets a
    stub that fails a contract, and its owner fills it in.
- **G1 and G2** meet at the `.objc` tables: G1 owns the format, G2 owns
  metal.objc.

**Merge order:**
1. C1–C4.
2. Phase 0's interfaces.
3. G1.
4. G4, which freezes the IR's first version.
5. G2, G5 and G7: the Metal path runs end to end.
6. G3 and G6: the Vulkan path.
7. G8.
8. G9 throughout, with its last commit last.

**Time.** About three weeks of agent work in parallel; G4 is the
largest task. On the release's own critical path:
- the migrations (A17 after 0.17.0, A18 after 0.18.0);
- the gate;
- the display row, run by hand.

### 6.4 Adapting the start-now code

| step | when | how |
|---|---|---|
| **A17 values** | after 0.17.0 | `fix --values` on compiler/std/{objc,gpu}: `self: *T` → `&self`/`&mut self`, `defer x.free()` deleted; `impl Drop` for `Id<T>` and each resource (the `free` bodies move into `drop`; `free` stays one release as the deprecated consuming alias, as for `Vec`); `map_read` gets `#[views(self)]`, passes take `&mut RenderPass`; `Ref<T>` becomes a view type; tests/gpu re-run under `--check-alloc` |
| **A18 contracts** | after 0.18.0 | one `refactor --script`: each function's leading `validate(c, Rule::X)` statements become `requires c` clauses with the rule as the message; `type BufferUsage = distinct u32` (and the other flag and id types), with `rewrite` for the constants; the interpreter-versus-backend tests become `#[property]` tests |
| **A21 threads** | after 0.21.0 | the `Sync`/`Send` declarations; `queue.on_done` over `Block` with owned closures; locks on the resource table and descriptor pools; multi-threaded encoding tests under 0.21's schedule checker |

## 7. Release gate additions

- `gpu-metal`, `wgsl` and `gpu-fuzz` (60 s per mode) on the Mac.
- `gpu-vulkan`, `wgsl` and `gpu-fuzz` in the gpu container image.
- `objcgen --check` (the tables against the runtime) and the generated
  files up to date.
- `leaks --atExit` on examples/gpu/compute and triangle.
- The bench gate (§5).
- **By hand, with a display:** examples/gpu/triangle-window on the Mac,
  recorded in docs/releases.md with the macOS version.

x86 rows stay off, per the standing instruction.

## 8. Risks

| # | risk | mitigation |
|---|---|---|
| R1 | **A wrong `objc_msgSend` prototype** is silent memory corruption, not an error | no prototype by hand: objcgen generates them and checks every one against the runtime's type encodings (S5), and `--check-unsafe` re-checks receivers at first call |
| R2 | **Retain/release mistakes** (+1 versus +0) crash late or leak | the table's `own`; `Id<T>` versus `Ref<T>`; retain-count assertions in std::objc's tests; `leaks --atExit` in the gate |
| R3 | **Callbacks on foreign threads** (S4) break single-threaded statics | none used before 0.21 (§2.11); a test asserts no std::gpu path passes a block to a handler API |
| R4 | **Objective-C exceptions** through tachyon frames | contracts run first; the uncaught-exception handler prints the reason; the abort is defined behaviour |
| R5 | **No GPU debugger** on this machine (Command Line Tools only) | `MTL_DEBUG_LAYER` and shader validation in every Metal test; the interpreter as the reference; Vulkan validation layers in the container |
| R6 | **lavapipe is not a real GPU**: it hides some synchronization bugs | synchronization validation; the barrier logic shared and unit-tested on recorded passes; a real Linux GPU run asked of the user before 1.0 (O5) |
| R7 | **The shader compiler's size and subtlety** (the uniformity analysis, layout rules) | the subset; the interpreter oracle; the fuzzer; naga's acceptance as a cross-check on the corpus |
| R8 | **Metal's run-time MSL compile adds start-up latency** | the OS shader cache (S1: 20 ms warm), the on-disk `PipelineCache`, compilation off the main thread from 0.21 |
| R9 | **The display rows cannot run unattended** | everything else is headless; the display rows are a short manual list |

## 9. Open questions

- **O1. Selector references in `__objc_selrefs`** (zero-cost selectors,
  as clang emits them). *Proposed:* only if the draw bench shows the
  cache's branch above 1%.
- **O2. Metal argument buffers and Vulkan push descriptors.** *Proposed:*
  0.22.x, if the draw bench shows binding cost dominating.
- **O3. `MTLHeap` sub-allocation and untracked resources on Metal.**
  *Proposed:* after the terminal measures its frame time; likely
  unneeded.
- **O4. Checking shaders in `tachyonc check`.** It needs the translator
  in compiler/src: possible from 0.23 under the release rule.
  *Proposed:* 0.23.x, with `include_str`'d `.wgsl` files checked as part
  of the program and their errors in the same one-line form.
- **O5. A real Linux GPU, and MoltenVK on the Mac,** for the Vulkan hal.
  *Proposed:* ask the user. Neither is gated.
- **O6. Objective-C headers in the C importer.** *Proposed:* not before
  1.0 unless users need broad Apple APIs.

### Critical files for implementation

- compiler/src/front/modules/lookup.tach and the module loader (C1);
  compiler/src/front/modules/stdsections.tach, front/stdsrc.tach and
  compiler/std/embed.sh (C2).
- compiler/src/front/cpp/directives.tach (`include`, `find_include`: C4's
  framework lookup); compiler/src/main.tach (option parsing: `-l`, `-L`,
  `-I` at lines 366–392) with back/objfile/output.tach
  (`add_link_arg`): C4's `-framework` and `-F`.
- compiler/src/front/cimport/mod.tach (`--emit-imports`, used to generate
  gpu/vk/sys.tach in the container).
- tests/run.sh (directives) and tests/abi/run.sh (the model for
  tests/gpu/run.sh); bootstrap/gate.sh and
  bootstrap/aarch64-linux-check.sh (the gpu image's row).
- New: compiler/std/objc/, compiler/std/gpu/ (hal.tach, core/,
  metal.macos.tach, vk.linux.tach, wgsl/), tools/objcgen/, tests/gpu/,
  bench/gpu/, examples/gpu/, compiler/guide/{gpu,objc}.md.

## Decisions taken (for the user's review)

All taken as recommended on 2026-10-16, under the standing instruction to
work autonomously through 0.23. Each can be revisited.

**Structure**
- D1. **wgpu's split, static dispatch:** `std::gpu` (API) over
  `gpu::core` (validation, lifetimes, tracking) over `trait hal::Api`
  with two implementations; no `dyn`, no run-time backend choice.
- D2. **The backend is chosen by OS-specific module files**
  (`metal.macos.tach`, `vk.linux.tach`; C1): every variant type-checked
  on every host, only the target's generated. This is not `cfg`, and not
  run-time dispatch.
- D3. **std grows submodules loaded on use** (`std::objc`, `std::gpu`,
  `std::window`; C2). Start-now code lives at its final path and ships
  only with its release.
- D4. **Commands are encoded immediately** into Metal's encoders; Vulkan
  records a pass and replays it after its barriers.

**Ownership and API**
- D5. **Resources are owned values with `Drop`**; dropping is always safe
  (deferred native destruction by submission index); bind groups, views
  and submissions hold internal references.
- D6. **Passes are closure-scoped views** (`enc.render_pass(&desc,
  |pass| ...)`). **Mapped ranges and frames are views**: wgpu's run-time
  mapping and pass checks become 0.17 compile errors.
- D7. **Validation is contracts** (§2.6, `gpu.*` codes, exit 101 on
  violation), always on; no error scopes; `Result` only for failures a
  correct program can meet.
- D8. **Flags and ids are distinct types (0.18)**; descriptors use
  default parameters.
- D9. **Allocation:** host memory from the instance's allocator,
  per-frame arenas, no `Gpa` allocation in steady-state frames (checked
  with `query effects`); a TLSF sub-allocator for Vulkan device memory.
- D10. **Effects:** device calls are `io`, and no new effect kind; the
  shader compiler is proven free of `io` and `global`.

**Backends**
- D11. **Metal first**, through `std::objc`: typed `objc_msgSend` shapes
  generated from `.objc` tables and checked against the runtime's type
  encodings; `Id<T>`/`Ref<T>` ownership; cached selectors; pools as
  closures; classes and blocks built in tachyon. Shared storage on Apple
  silicon. macOS 14 is the floor.
- D12. **Vulkan 1.3 second**: `dlopen` plus a function table, bindings
  generated from `vulkan_core.h` 1.3.239 and checked in; dynamic
  rendering, synchronization2, timeline semaphores.
- D13. **No callbacks off the main thread before 0.21.**

**Shaders**
- D14. **A WGSL subset** (§2.10's table), translated at run time by
  `dev.shader(src)`, with `include_str` for sources (C3): IR shared by
  three outputs (MSL 3.0, SPIR-V 1.3, a CPU interpreter).
- D15. **No undefined behaviour in shaders**: WGSL's definitions for
  division, every index checked (clamp, or read zero and skip the write),
  checks removed only where a dominating comparison proves them.
- D16. **The interpreter is the oracle**, with a differential shader
  fuzzer against Metal and lavapipe in every gate.

**Process**
- D17. **Everything starts now** except the migrations (A17, A18) and
  the threading items (A21). The compiler enablers C1–C4 come first.
- D18. **Testing:** headless on the Mac (compute and render to texture
  under Metal validation) and in a new gpu container image (lavapipe,
  spirv-val, validation layers, Xvfb, weston); display tests by hand
  before a release.
- D19. **Performance goals** as in §5: within 10% of Objective-C on
  draw encoding, faster than wgpu, validation under 3%, shader bounds
  checks under 5%, translation no slower than naga.

## Appendix: spike sources

The spikes live in the design branch's scratch directory, not in the
tree. Their essential lines:

- **S2's clear colour** (an HFA in v0–v3):
  `#[link_name = "objc_msgSend"] fn msg_clear(o: *u8, s: *u8, c:
  MTLClearColor);` with `#[repr(C)] struct MTLClearColor { r: f64, g:
  f64, b: f64, a: f64 }`.
- **S3's IMP:**
  `extern "C" fn mul_add(this: *u8, cmd: *u8, a: i64, b: i64) -> i64 { a
  * b + 1 }`, registered through `fn class_addMethod(cls: *u8, sel: *u8,
  imp: extern "C" fn(*u8, *u8, i64, i64) -> i64, types: *u8) -> bool;`
  with types `"q@:qq"`.
- **S4's block:**
  `#[repr(C)] struct Block { isa: *u8, flags: i32, reserved: i32, invoke:
  extern "C" fn(*Block, *u8), desc: *BlockDesc, ctx: *i64 }`, with
  `isa: &_NSConcreteGlobalBlock as *u8` (an `extern "C" static`) and
  `flags: 1 << 28`.
- **S5's check:** `fn protocol_getMethodDescription(p: *u8, s: *u8,
  required: bool, instance: bool) -> MethodDesc;` returns a 16-byte
  struct in x0/x1. The type strings were identical for the protocol and
  for the concrete class `AGXG17GDevice`.

## 0.22.0 as built: std::gpu on Metal

Written on release-0.20's tree (value semantics, contracts, std's module
tree); the scope of 0.22.0 is Metal, with Vulkan and the shader
compiler's other outputs in 0.22.x.

- **Where it is.** `std::objc` (compiler/std/objc/: `Id<T>` owned, with
  Drop sending release; `Ref<T>` a view of what keeps the object alive;
  pools; frameworks opened at run time), `std::gpu` (compiler/std/gpu/:
  the public API, `types`, `shader`), `std::gpu::hal` (the backend
  traits) and `std::gpu::hal::metal` (with `sys`, generated by
  tools/objcgen from compiler/std/objc/tables/metal.objc: 184 methods
  checked against the runtime's encodings, every constant and struct
  against the SDK's headers). Every section is lazy behind the gate words
  `gpu` and `objc` (compiler/std/index.awk): a program that names neither
  reads none of it, and compiles as fast as before.
- **Linking without C4.** A program links libobjc (`tachyonc prog.tach -l
  objc`); std::objc opens Foundation, Metal and QuartzCore with `dlopen`
  and reaches their C functions with `dlsym`, so no `-framework` is
  needed. `import` of framework headers is not used at all.
- **What differs from §2.**
  - Contracts are `requires ... else "gpu.CODE: ..."` clauses and
    `assert(cond, "gpu.CODE: ...")` inside loops; the codes are §2.6's,
    plus `gpu.state` (a mapped buffer used) and `gpu.unsupported` (a
    capability the device lacks).
  - Flags stay `u32` constants in modules (`BufferUsage::STORAGE`): a
    distinct type cannot have named constants yet.
  - `Ref<T>` is a view (it holds a `&u8` of its owner), so a +0 reference
    cannot outlive the `Id` it came from; autoreleased results view the
    receiver they came from.
  - `map_read(&mut self, &dev) -> [u8]` and `map_write(..) -> &mut [u8]`
    are views of the buffer; `unmap(&dev)` ends a map_write (a no-op on
    Metal's shared memory, a copy on a discrete-memory backend).
  - Surfaces: `inst.surface(&dev, RawSurface::MetalLayer(p))` for
    std::window's layer, `RawSurface::Headless` for an unattached layer
    (tested: frames taken, drawn, read back, presented).
  - Command buffers retain what they use (Metal's default), so dropping a
    resource while it is in flight is safe without submission tracking;
    unretained command buffers wait for the draw bench to ask (O1).
- **Tests.** tests/gpu/run.sh (26 cases, category `gpu` of tests/run.sh,
  skipped off macOS): compute against the CPU, render to texture against
  reference images drawn by a CPU rasterizer, the contracts, surfaces,
  std::objc's retain counts and exceptions, objcgen's checks; every case
  under `MTL_DEBUG_LAYER`/`MTL_SHADER_VALIDATION` and `leaks --atExit`.
  examples/gpu/{compute,triangle} with `REQUIRES: metal` test cases.

### CUDA readiness

The backend layer is shaped so that a compute-only backend such as CUDA
is added without touching the public API:

1. **The traits.** `hal::Api` is everything compute needs: adapters,
   devices, buffers, textures and samplers, shaders, compute pipelines,
   bind groups, copies, submission, waits. Rendering is a second trait,
   `hal::Render<B: Api>`, which a compute-only backend does not
   implement. No stub functions.
2. **Capabilities.** `hal::Caps { compute, render, surfaces, textures,
   unified_memory, shader_kind }`, reported per device; every render,
   surface and texture entry point of std::gpu `requires` its capability
   (`gpu.unsupported` otherwise), so a CUDA device fails cleanly where it
   cannot draw.
3. **No Metal in the public API.** Memory is reached only by
   `map_read`/`map_write`/`unmap` (a discrete-memory backend stages;
   `unified_memory` is information only); queues only submit, write and
   wait (CUDA: a stream, `cuStreamSynchronize`); shaders are a
   `ShaderSource { kind: ShaderKind::{Msl, Spirv, Ptx}, code, reflection }`
   whose reflection gives *native* slots (a Metal buffer index, a CUDA
   kernel parameter index), never Metal's numbering.
4. **What a CUDA backend writes.** `std::gpu::hal::cuda` (Linux, Windows):
   the driver API opened with `dlopen("libcuda.so")` as Metal is (no
   link-time dependency), `cuModuleLoadData` on the PTX the shader
   compiler emits for `ShaderKind::Ptx`, a bind group as the kernel's
   parameter block, `cuLaunchKernel` for `dispatch`, `cuMemcpy*Async` for
   copies and staging, `cuMemAllocHost` shadows for mapping, Caps with
   `render: false, surfaces: false`.
5. **What stands in the way, in the compiler.** One backend per build:
   std::gpu names its backend through a module alias, because a type
   alias of a generic struct over an associated type fails ("'Metal' has
   no associated type ..."; reported with tools/agent-feedback). When it
   works, `gpu::core::Device<A: hal::Api>` becomes the public types'
   implementation and `gpu::cuda::Device = core::Device<Cuda>` lives
   next to the native one, in one program. Until then a CUDA build
   chooses the backend as the OS-specific files (C1) will.
6. **Tests.** tests/gpu/run.sh's compute cases are backend-neutral but
   for their MSL: with the WGSL compiler they take WGSL, and a `NEEDS:
   cuda` directive runs them on the CUDA backend where a GPU is present.
