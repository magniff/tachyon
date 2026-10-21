// The uniform and storage layouts: vec3 members followed by scalars,
// matrices with padded columns, nested structs, arrays of vec3.
// JOB: dispatch 1 1 1
// JOB: buffer 0 0 256 random 21
// JOB: buffer 0 1 256

struct Inner {
    a: vec3<u32>,
    b: u32,
    c: vec2<u32>,
}

struct Params {
    m: mat3x3<f32>,
    v: vec3<u32>,
    s: u32,
    inner: Inner,
    arr: array<vec4<u32>, 2>,
    w: vec2<u32>,
    t: u32,
}

@group(0) @binding(0) var<uniform> params: Params;
@group(0) @binding(1) var<storage, read_write> out: array<u32>;

@compute @workgroup_size(1)
fn main() {
    out[0] = bitcast<u32>(params.m[0].x);
    out[1] = bitcast<u32>(params.m[1].z);
    out[2] = bitcast<u32>(params.m[2].y);
    out[3] = params.v.x;
    out[4] = params.v.z;
    out[5] = params.s;
    out[6] = params.inner.a.y;
    out[7] = params.inner.b;
    out[8] = params.inner.c.y;
    out[9] = params.arr[1].w;
    out[10] = params.w.x;
    out[11] = params.t;
    let p = params;
    out[12] = p.inner.b + p.t;
    let inner = p.inner;
    out[13] = inner.a.x + inner.c.x;
    var copy: Inner = params.inner;
    copy.a.z = 5u;
    out[14] = copy.a.z + copy.b;
}
