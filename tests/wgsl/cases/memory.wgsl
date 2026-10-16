// Indices out of range: fixed-size arrays, vectors and matrices clamp;
// runtime-sized arrays read zero and skip writes; arrayLength; vec3 in
// structs (WGSL's layout); arrays of structs.
// JOB: dispatch 1 1 1
// JOB: buffer 0 0 64 random 11
// JOB: buffer 0 1 96
// JOB: buffer 0 2 512

struct Item {
    pos: vec3<f32>,
    id: u32,
    tags: array<u32, 3>,
    scale: f32,
}

struct Items {
    count: u32,
    items: array<Item>,
}

@group(0) @binding(0) var<storage, read> src: array<u32>;
@group(0) @binding(1) var<storage, read_write> items: Items;
@group(0) @binding(2) var<storage, read_write> out: array<u32>;

@compute @workgroup_size(1)
fn main() {
    var arr = array<u32, 4>(10u, 20u, 30u, 40u);
    let big = src[0] | 8u;
    let neg = -1;
    out[0] = arr[big];
    out[1] = arr[neg];
    arr[big] = 99u;
    out[2] = arr[3];
    var v = vec4<u32>(1u, 2u, 3u, 4u);
    out[3] = v[big];
    v[big] = 7u;
    out[4] = v.w;
    var m = mat3x3<f32>(vec3(1.0, 2.0, 3.0), vec3(4.0, 5.0, 6.0), vec3(7.0, 8.0, 9.0));
    out[5] = bitcast<u32>(m[big].y);
    out[6] = src[1000u];
    out[7] = src[big + 1000000u];
    out[8] = arrayLength(&src);
    out[9] = arrayLength(&items.items);
    out[10] = arrayLength(&out);
    out[1000] = 5u;
    let k = arrayLength(&items.items);
    for (var i = 0u; i < k + 2u; i++) {
        items.items[i].pos = vec3<f32>(f32(i), 1.0, 2.0);
        items.items[i].id = i + 100u;
        items.items[i].tags[i] = i;
        items.items[i].scale = 0.5;
    }
    items.count = k;
    let it = items.items[1];
    out[11] = it.id;
    out[12] = bitcast<u32>(it.pos.x + it.pos.y + it.scale);
    out[13] = items.items[7].id;
    var local = array<Item, 2>();
    local[1] = it;
    local[big].tags[big] = 77u;
    out[14] = local[1].tags[2];
    out[15] = local[1].id;
    let row = vec3<u32>(src[2], src[3], src[4]);
    out[16] = row[src[5] % 3u];
}
