// ERROR: error wgsl.access: cannot write to a read-only storage variable
// ERROR: help: declare it 'var<storage, read_write>'
@group(0) @binding(0) var<storage> data: array<u32>;
@compute @workgroup_size(64)
fn main(@builtin(global_invocation_id) id: vec3<u32>) {
    data[id.x] = 1u;
}
