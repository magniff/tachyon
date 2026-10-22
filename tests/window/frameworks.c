/* The Apple frameworks lib/shim, lib/window and examples/term/render
 * use, as a link input: each line becomes an LC_LINKER_OPTION load
 * command, so `tachyonc main.tach lib/shim/frameworks.c -o prog` links
 * them with no -framework flag (tachyonc rejects it until 0.22's C4).
 * The anchors reference one symbol of each framework that is otherwise
 * reached only through objc_getClass, so the linker keeps it. */
__asm__(".linker_option \"-framework\", \"AppKit\"");
__asm__(".linker_option \"-framework\", \"QuartzCore\"");
__asm__(".linker_option \"-framework\", \"Metal\"");
__asm__(".linker_option \"-framework\", \"CoreText\"");
__asm__(".linker_option \"-framework\", \"CoreGraphics\"");
__asm__(".linker_option \"-framework\", \"CoreFoundation\"");
__asm__(".linker_option \"-framework\", \"Foundation\"");
__asm__(".linker_option \"-lobjc\"");

extern void *NSApp;
extern void *kCAGravityResize;
extern void *MTLCreateSystemDefaultDevice(void);
void *const tachyon_framework_anchors[] = {
    &NSApp,
    &kCAGravityResize,
    (void *)MTLCreateSystemDefaultDevice,
};
