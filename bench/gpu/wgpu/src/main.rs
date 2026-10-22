// bench/gpu: CPU cost of encoding DRAWS draws with a bind group change
// every 10 into one render pass (wgpu on Metal). Prints the median of the
// iterations in microseconds, as draws.vl and draws.m do.
use std::time::Instant;

const DRAWS: usize = 10_000;
const GROUPS: usize = 16;
const ITERS: usize = 60;

const SHADER: &str = r#"
struct Globals { size: vec2<f32>, pad: vec2<f32> };
@group(0) @binding(0) var<uniform> g: Globals;
struct VOut { @builtin(position) pos: vec4<f32>, @location(0) color: vec4<f32> };
@vertex fn vs(@location(0) pos: vec2<f32>, @location(1) color: vec4<f32>) -> VOut {
    let n = pos / g.size * 2.0 - 1.0;
    return VOut(vec4<f32>(n.x, -n.y, 0.5, 1.0), color);
}
@fragment fn fs(v: VOut) -> @location(0) vec4<f32> { return v.color; }
"#;

fn main() {
    pollster::block_on(run());
}

async fn run() {
    let mut desc = wgpu::InstanceDescriptor::new_without_display_handle();
    desc.backends = wgpu::Backends::METAL;
    let instance = wgpu::Instance::new(desc);
    let adapter = instance.request_adapter(&wgpu::RequestAdapterOptions::default()).await.expect("adapter");
    let (device, queue) = adapter.request_device(&wgpu::DeviceDescriptor::default()).await.expect("device");
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor { label: None, source: wgpu::ShaderSource::Wgsl(SHADER.into()) });
    let bgl = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
        label: None,
        entries: &[wgpu::BindGroupLayoutEntry {
            binding: 0,
            visibility: wgpu::ShaderStages::VERTEX,
            ty: wgpu::BindingType::Buffer { ty: wgpu::BufferBindingType::Uniform, has_dynamic_offset: false, min_binding_size: None },
            count: None,
        }],
    });
    let layout = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor { label: None, bind_group_layouts: &[Some(&bgl)], immediate_size: 0 });
    let pipeline = device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
        label: None,
        layout: Some(&layout),
        vertex: wgpu::VertexState {
            module: &shader,
            entry_point: Some("vs"),
            compilation_options: Default::default(),
            buffers: &[Some(wgpu::VertexBufferLayout {
                array_stride: 12,
                step_mode: wgpu::VertexStepMode::Vertex,
                attributes: &[
                    wgpu::VertexAttribute { format: wgpu::VertexFormat::Float32x2, offset: 0, shader_location: 0 },
                    wgpu::VertexAttribute { format: wgpu::VertexFormat::Unorm8x4, offset: 8, shader_location: 1 },
                ],
            })],
        },
        fragment: Some(wgpu::FragmentState {
            module: &shader,
            entry_point: Some("fs"),
            compilation_options: Default::default(),
            targets: &[Some(wgpu::ColorTargetState { format: wgpu::TextureFormat::Rgba8Unorm, blend: None, write_mask: wgpu::ColorWrites::ALL })],
        }),
        primitive: Default::default(),
        depth_stencil: None,
        multisample: Default::default(),
        multiview_mask: None,
        cache: None,
    });
    let tex = device.create_texture(&wgpu::TextureDescriptor {
        label: None,
        size: wgpu::Extent3d { width: 64, height: 64, depth_or_array_layers: 1 },
        mip_level_count: 1,
        sample_count: 1,
        dimension: wgpu::TextureDimension::D2,
        format: wgpu::TextureFormat::Rgba8Unorm,
        usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
        view_formats: &[],
    });
    let view = tex.create_view(&Default::default());
    let verts = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: 6 * 12, usage: wgpu::BufferUsages::VERTEX, mapped_at_creation: false });
    let uni = device.create_buffer(&wgpu::BufferDescriptor { label: None, size: (GROUPS * 256) as u64, usage: wgpu::BufferUsages::UNIFORM, mapped_at_creation: false });
    let groups: Vec<wgpu::BindGroup> = (0..GROUPS)
        .map(|k| {
            device.create_bind_group(&wgpu::BindGroupDescriptor {
                label: None,
                layout: &bgl,
                entries: &[wgpu::BindGroupEntry {
                    binding: 0,
                    resource: wgpu::BindingResource::Buffer(wgpu::BufferBinding { buffer: &uni, offset: (k * 256) as u64, size: wgpu::BufferSize::new(16) }),
                }],
            })
        })
        .collect();
    let mut times = Vec::new();
    for _ in 0..ITERS {
        let t0 = Instant::now();
        let mut enc = device.create_command_encoder(&Default::default());
        {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: None,
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations { load: wgpu::LoadOp::Clear(wgpu::Color::BLACK), store: wgpu::StoreOp::Store },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
                multiview_mask: None,
            });
            pass.set_pipeline(&pipeline);
            pass.set_vertex_buffer(0, verts.slice(..));
            for i in 0..DRAWS {
                if i % 10 == 0 {
                    pass.set_bind_group(0, &groups[(i / 10) % GROUPS], &[]);
                }
                pass.draw(0..6, 0..1);
            }
        }
        let cmd = enc.finish();
        let dt = t0.elapsed();
        queue.submit([cmd]);
        device.poll(wgpu::PollType::wait_indefinitely()).unwrap();
        times.push(dt.as_secs_f64() * 1e6);
    }
    times.sort_by(|a, b| a.partial_cmp(b).unwrap());
    println!("wgpu {} draws: median {:.0} us, min {:.0} us", DRAWS, times[times.len() / 2], times[0]);
}
