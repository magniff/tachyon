// A textured, instanced quad: vertex attributes, a uniform matrix,
// sampling (implicit, biased, explicit level; an array texture; a depth
// comparison), derivatives, discard, linear and flat interpolation, a
// depth output. Compiled by Metal (no job: sampling is not run alone).

struct Camera { view_proj: mat4x4<f32>, tint: vec4<f32> }

@group(0) @binding(0) var<uniform> cam: Camera;
@group(0) @binding(1) var tex: texture_2d<f32>;
@group(0) @binding(2) var layers: texture_2d_array<f32>;
@group(0) @binding(3) var smp: sampler;
@group(0) @binding(4) var shadow: texture_depth_2d;
@group(0) @binding(5) var cmp: sampler_comparison;

struct VIn {
    @location(0) pos: vec3<f32>,
    @location(1) uv: vec2<f32>,
    @location(2) offset: vec2<f32>,
    @builtin(instance_index) inst: u32,
}

struct VOut {
    @builtin(position) clip: vec4<f32>,
    @location(0) uv: vec2<f32>,
    @location(1) @interpolate(linear) shade: f32,
    @location(2) @interpolate(flat) layer: u32,
}

@vertex
fn vs(v: VIn) -> VOut {
    var o: VOut;
    o.clip = cam.view_proj * vec4<f32>(v.pos + vec3<f32>(v.offset, 0.0), 1.0);
    o.uv = v.uv;
    o.shade = f32(v.inst % 4u) * 0.25;
    o.layer = v.inst % 3u;
    return o;
}

struct FOut {
    @location(0) color: vec4<f32>,
    @builtin(frag_depth) depth: f32,
}

@fragment
fn fs(i: VOut) -> FOut {
    let base = textureSample(tex, smp, i.uv);
    let blur = textureSampleBias(tex, smp, i.uv, 1.0);
    let l = textureSampleLevel(layers, smp, i.uv, i.layer, 0.0);
    let lit = textureSampleCompare(shadow, cmp, i.uv, 0.5);
    let edge = fwidth(i.uv.x) + abs(dpdy(i.uv.y));
    if base.a < 0.01 {
        discard;
    }
    let size = textureDimensions(tex);
    let texel = textureLoad(tex, vec2<i32>(i.uv * vec2<f32>(size)), 0);
    var o: FOut;
    o.color = mix(base, blur, 0.5) * l * cam.tint * (lit + edge) + texel * i.shade;
    o.depth = clamp(i.clip.z, 0.0, 1.0);
    return o;
}
