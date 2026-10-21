// A compute shader writing a storage texture (bounds checked by
// textureDimensions) and reading one level of a sampled texture.

@group(0) @binding(0) var src: texture_2d<f32>;
@group(0) @binding(1) var dst: texture_storage_2d<rgba8unorm, write>;
@group(0) @binding(2) var<storage, read_write> hist: array<atomic<u32>, 16>;

@compute @workgroup_size(8, 8)
fn blur(@builtin(global_invocation_id) id: vec3<u32>) {
    let p = vec2<i32>(id.xy);
    var acc = vec4<f32>(0.0);
    for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
            acc += textureLoad(src, p + vec2<i32>(dx, dy), 0);
        }
    }
    let c = acc / 9.0;
    textureStore(dst, p, c);
    let bucket = u32(clamp(c.r * 16.0, 0.0, 15.0));
    atomicAdd(&hist[bucket], 1u);
}
