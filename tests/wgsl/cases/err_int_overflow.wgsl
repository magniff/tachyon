// ERROR: error wgsl.const: this i32 literal is above 2147483647
@compute @workgroup_size(1)
fn main() {
    let x = 2147483648i;
}
