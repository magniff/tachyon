# triangle: render to a texture, read it back

A triangle with a color per vertex, drawn into a 48 x 20 texture,
copied to a buffer, mapped and printed: one character a pixel, after the
channel that dominates it.

```sh
tachyonc main.tach -l objc -o triangle && ./triangle
```

```text
................................................
.......................RR.......................
......................RRRR......................
...
...GGGGGGGGGGGGGGGGGGGGGBBBBBBBBBBBBBBBBBBBBB...
................................................
```

- The vertex buffer holds `x, y, r, g, b` per vertex; its
  `VertexLayout::new(20)` gives the two attributes' formats and offsets,
  which must match the shader's inputs (`refl.input`): a mismatch is
  `gpu.format` at `dev.render_pipeline`.
- `gpu::RenderDesc::new(&shader, "vs", "fs", Format::Rgba8Unorm)` names
  the entry points and the target's format; `desc.vertex_buffer(layout)`,
  `desc.blend(..)`, `desc.depth(..)` change the rest.
- `enc.render_pass(PassDesc::color(&view), |pass| { ... })`: the target
  is cleared (to black by default), drawn into, and stored.
- `enc.copy_texture_to_buffer(&target, &pixels, 256)`: rows 256 bytes
  apart (WebGPU's alignment), so a pixel is at `y * 256 + x * 4`.
