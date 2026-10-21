// bench/gpu: CPU cost of encoding DRAWS draws with a bind group change
// every 10 into one render pass, in Objective-C (clang -O2, ARC): the
// baseline of docs/design/gpu.md §5 for draws.tach. A "bind group" here is
// what the tachyon one does on Metal: a setVertexBuffer:offset:atIndex:
// of a 256-byte slice of one uniform buffer.
//   clang -O2 -fobjc-arc bench/gpu/draws.m -framework Metal -framework Foundation -o draws-objc
#import <Metal/Metal.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>

enum { DRAWS = 10000, GROUPS = 16, ITERS = 60 };

static const char *MSL =
    "#include <metal_stdlib>\n"
    "using namespace metal;\n"
    "struct Globals { float2 size; };\n"
    "struct VIn { float2 pos [[attribute(0)]]; float4 color [[attribute(1)]]; };\n"
    "struct VOut { float4 pos [[position]]; float4 color; };\n"
    "vertex VOut vs_main(VIn in [[stage_in]], constant Globals& g [[buffer(0)]]) {\n"
    "    VOut o; float2 n = in.pos / g.size * 2.0 - 1.0;\n"
    "    o.pos = float4(n.x, -n.y, 0.5, 1.0); o.color = in.color; return o;\n"
    "}\n"
    "fragment float4 fs_main(VOut in [[stage_in]]) { return in.color; }\n";

static int cmp(const void *a, const void *b) {
    double x = *(const double *)a, y = *(const double *)b;
    return x < y ? -1 : x > y;
}

int main(void) {
    @autoreleasepool {
        id<MTLDevice> dev = MTLCreateSystemDefaultDevice();
        id<MTLCommandQueue> queue = [dev newCommandQueue];
        NSError *err = nil;
        MTLCompileOptions *opts = [MTLCompileOptions new];
        opts.languageVersion = MTLLanguageVersion3_0;
        id<MTLLibrary> lib = [dev newLibraryWithSource:[NSString stringWithUTF8String:MSL] options:opts error:&err];
        if (!lib) { fprintf(stderr, "%s\n", err.localizedDescription.UTF8String); return 1; }
        MTLRenderPipelineDescriptor *pd = [MTLRenderPipelineDescriptor new];
        pd.vertexFunction = [lib newFunctionWithName:@"vs_main"];
        pd.fragmentFunction = [lib newFunctionWithName:@"fs_main"];
        pd.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA8Unorm;
        MTLVertexDescriptor *vd = [MTLVertexDescriptor new];
        vd.attributes[0].format = MTLVertexFormatFloat2;
        vd.attributes[0].offset = 0;
        vd.attributes[0].bufferIndex = 30;
        vd.attributes[1].format = MTLVertexFormatUChar4Normalized;
        vd.attributes[1].offset = 8;
        vd.attributes[1].bufferIndex = 30;
        vd.layouts[30].stride = 12;
        pd.vertexDescriptor = vd;
        id<MTLRenderPipelineState> pipe = [dev newRenderPipelineStateWithDescriptor:pd error:&err];
        if (!pipe) { fprintf(stderr, "%s\n", err.localizedDescription.UTF8String); return 1; }
        MTLTextureDescriptor *td = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm width:64 height:64 mipmapped:NO];
        td.usage = MTLTextureUsageRenderTarget;
        td.storageMode = MTLStorageModePrivate;
        id<MTLTexture> tex = [dev newTextureWithDescriptor:td];
        id<MTLBuffer> verts = [dev newBufferWithLength:6 * 12 options:MTLResourceStorageModeShared];
        id<MTLBuffer> uni = [dev newBufferWithLength:GROUPS * 256 options:MTLResourceStorageModeShared];
        double times[ITERS];
        for (int it = 0; it < ITERS; it++) {
            @autoreleasepool {
                uint64_t t0 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
                id<MTLCommandBuffer> cb = [queue commandBuffer];
                MTLRenderPassDescriptor *rp = [MTLRenderPassDescriptor new];
                rp.colorAttachments[0].texture = tex;
                rp.colorAttachments[0].loadAction = MTLLoadActionClear;
                rp.colorAttachments[0].storeAction = MTLStoreActionStore;
                rp.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
                id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:rp];
                [enc setRenderPipelineState:pipe];
                [enc setCullMode:MTLCullModeNone];
                [enc setFrontFacingWinding:MTLWindingCounterClockwise];
                [enc setVertexBuffer:verts offset:0 atIndex:30];
                for (int i = 0; i < DRAWS; i++) {
                    if (i % 10 == 0) {
                        [enc setVertexBuffer:uni offset:((i / 10) % GROUPS) * 256 atIndex:0];
                    }
                    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:6 instanceCount:1 baseInstance:0];
                }
                [enc endEncoding];
                uint64_t t1 = clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW);
                [cb commit];
                [cb waitUntilCompleted];
                times[it] = (t1 - t0) / 1000.0;
            }
        }
        qsort(times, ITERS, sizeof times[0], cmp);
        printf("objc %d draws: median %.0f us, min %.0f us\n", DRAWS, times[ITERS / 2], times[0]);
    }
    return 0;
}
