// ERROR: error wgsl.index: index 4 is out of range: the length is 4
@compute @workgroup_size(1)
fn main() {
    var a = array<u32, 4>();
    a[4] = 1u;
}
