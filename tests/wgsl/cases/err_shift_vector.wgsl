// ERROR: error wgsl.const: a constant shift amount is below 32
@compute @workgroup_size(1)
fn main() {
    var v = vec2<u32>(1u, 2u);
    v = v << vec2<u32>(1u, 32u);
}
