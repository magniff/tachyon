#include <stdio.h>
#include <stdint.h>
enum Kind { Push, Load, Store, Add, Mul, Rem, Lt, JumpIfZero, Jump, Halt };
typedef struct { enum Kind kind; int64_t arg; } Op;
typedef struct { int64_t stack[16]; uint64_t sp; int64_t regs[4]; } Vm;
static void run(Vm *vm, const Op *code) {
    uint64_t pc = 0;
    for (;;) {
        Op op = code[pc];
        int64_t a, b;
        switch (op.kind) {
        case Push: vm->stack[vm->sp++] = op.arg; break;
        case Load: vm->stack[vm->sp++] = vm->regs[op.arg]; break;
        case Store: vm->regs[op.arg] = vm->stack[--vm->sp]; break;
        case Add: b = vm->stack[--vm->sp]; a = vm->stack[--vm->sp]; vm->stack[vm->sp++] = a + b; break;
        case Mul: b = vm->stack[--vm->sp]; a = vm->stack[--vm->sp]; vm->stack[vm->sp++] = a * b; break;
        case Rem: b = vm->stack[--vm->sp]; a = vm->stack[--vm->sp]; vm->stack[vm->sp++] = b ? a % b : a; break;
        case Lt: b = vm->stack[--vm->sp]; a = vm->stack[--vm->sp]; vm->stack[vm->sp++] = a < b; break;
        case JumpIfZero: if (vm->stack[--vm->sp] == 0) { pc = op.arg; continue; } break;
        case Jump: pc = op.arg; continue;
        case Halt: return;
        }
        pc++;
    }
}
int main(void) {
    const Op code[36] = {
        {Push, 2}, {Store, 0}, {Push, 0}, {Store, 1},
        {Load, 0}, {Push, 150000}, {Lt, 0}, {JumpIfZero, 35},
        {Push, 2}, {Store, 2},
        {Load, 0}, {Load, 2}, {Load, 2}, {Mul, 0}, {Lt, 0}, {JumpIfZero, 17},
        {Jump, 26},
        {Load, 0}, {Load, 2}, {Rem, 0}, {JumpIfZero, 30},
        {Load, 2}, {Push, 1}, {Add, 0}, {Store, 2}, {Jump, 10},
        {Load, 1}, {Push, 1}, {Add, 0}, {Store, 1},
        {Load, 0}, {Push, 1}, {Add, 0}, {Store, 0}, {Jump, 4},
        {Halt, 0},
    };
    Vm vm = {{0}, 0, {0}};
    run(&vm, code);
    printf("%ld\n", (long)vm.regs[1]);
    return 0;
}
