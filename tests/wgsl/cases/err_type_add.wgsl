// ERROR: error wgsl.type: '+' cannot take vec3<f32> and i32
// ERROR: help: convert one side: f32(...)
@compute @workgroup_size(1)
fn main() {
    let v = vec3<f32>(1.0);
    let k = 2i;
    let w = v + k;
}
