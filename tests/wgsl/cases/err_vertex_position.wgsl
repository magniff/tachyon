// ERROR: error wgsl.entry: a vertex shader returns '@builtin(position)' (a vec4<f32>)
@vertex
fn vs() -> @location(0) vec4<f32> {
    return vec4<f32>(0.0);
}
