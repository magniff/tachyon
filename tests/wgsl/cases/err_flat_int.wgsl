// ERROR: error wgsl.entry: '@location(0)' is an integer: it needs '@interpolate(flat)'
struct V { @builtin(position) p: vec4<f32>, @location(0) id: u32 }
@vertex
fn vs() -> V {
    return V(vec4<f32>(0.0), 1u);
}
