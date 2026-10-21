// ERROR: err_unknown_name.wgsl:5:12: error wgsl.name: unknown name 'colour'
@fragment
fn fs() -> @location(0) vec4<f32> {
    let c = vec4<f32>(1.0);
    return colour;
}
