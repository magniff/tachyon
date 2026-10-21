# std::gpu: compute and rendering on the GPU

Tachyon 0.22 has GPU support in std, on wgpu's model: an instance, an
adapter, a device and its queue; buffers (mapped to read and write them),
textures, views and samplers; shaders, bind groups and compute and render
pipelines; command encoders whose passes are closures; surfaces for
windows. On macOS it runs on Metal. A program links the Objective-C
runtime with `-l objc`; std opens Metal itself. `tachyonc guide gpu` is
the whole story.

| example | the program | what it shows |
|---|---|---|
| [compute](compute/) | Collatz step counts for 2^20 numbers, one GPU invocation each | a compute pipeline from MSL and its reflection, a bind group from the pipeline's layout, a dispatch, a copy, `map_read`, the result checked against the CPU |
| [triangle](triangle/) | a triangle rendered to a texture and printed as text | a vertex buffer and its layout, a render pipeline, a render pass into a texture, `copy_texture_to_buffer` and readback |

Each has a test case, `tests/examples/gpu-NAME.test` (`REQUIRES: metal`:
skipped off macOS). The library's own tests, headless and under Metal's
validation and `leaks`, are `tests/gpu/run.sh`.
