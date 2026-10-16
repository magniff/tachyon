// Workgroup memory with barriers (a tree reduction), atomics in storage
// and workgroup memory, workgroupUniformLoad.
// JOB: dispatch 4 1 1
// JOB: buffer 0 0 1024 random 3
// JOB: buffer 0 1 64
// JOB: buffer 0 2 32

@group(0) @binding(0) var<storage, read> data: array<u32>;
@group(0) @binding(1) var<storage, read_write> sums: array<u32>;
@group(0) @binding(2) var<storage, read_write> counters: array<atomic<u32>, 8>;

var<workgroup> partial: array<u32, 64>;
var<workgroup> hits: atomic<u32>;
var<workgroup> leader: u32;

@compute @workgroup_size(64)
fn main(@builtin(local_invocation_index) li: u32, @builtin(workgroup_id) wid: vec3<u32>, @builtin(num_workgroups) nw: vec3<u32>) {
    let i = wid.x * 64u + li;
    partial[li] = data[i] & 0xffffu;
    if li == 5u {
        leader = wid.x + 1u;
    }
    workgroupBarrier();
    for (var s = 32u; s > 0u; s = s >> 1u) {
        if li < s {
            partial[li] += partial[li + s];
        }
        workgroupBarrier();
    }
    if li == 0u {
        sums[wid.x] = partial[0];
    }
    atomicAdd(&hits, 1u);
    atomicAdd(&counters[0], data[i] & 15u);
    atomicMax(&counters[1], data[i] >> 8u);
    atomicMin(&counters[2], 0xffffffffu - (data[i] & 0xffffu));
    atomicOr(&counters[3], 1u << (li % 32u));
    atomicXor(&counters[4], li);
    let l = workgroupUniformLoad(&leader);
    workgroupBarrier();
    if li == 63u {
        atomicAdd(&counters[5], atomicLoad(&hits) * l);
        sums[nw.x + wid.x] = l;
    }
}
