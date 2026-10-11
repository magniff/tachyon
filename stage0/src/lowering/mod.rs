// Lowering: the type-checked AST to the IR (see ir.rs).
//
// Every local lives in a stack slot and every compound value in memory; a
// vreg holds a scalar or the address of a compound value. Expressions are
// lowered in one of three ways:
//   lower_value    to a vreg (a scalar, or the address of a compound)
//   lower_into     written to memory at a given address
//   lower_effect   for side effects only
//
//   ir.rs       the IR
//   layout.rs   sizes, alignments and field offsets
//   program.rs  statics, externs and functions
//   stmt.rs     blocks, statements, assignment and `return`
//   control.rs  `if` and loops
//   expr.rs     expressions
//   place.rs    addresses of places
//   ops.rs      operators and casts
//   call.rs     calls
//   print.rs    the textual form of the IR

use std::collections::HashMap;

use crate::parser::{Expr, Program};
use crate::typechecker::{CheckedProgram, TypeInternal};

mod call;
mod control;
mod expr;
mod ir;
mod layout;
mod ops;
mod place;
mod print;
mod program;
mod stmt;

pub use ir::*;
use layout::is_compound;
pub use layout::{Layout, field_offsets, layout_of, type_internal_to_ir};
pub use print::print_ir;

// A loop that `break`/`continue` can target.
struct LoopTarget {
    label: Option<String>,
    continue_block: BlockId,
    break_block: BlockId,
    // Where `break value` stores the loop's value.
    result: Option<(VReg, TypeInternal)>,
}

struct Lowerer<'a> {
    checked: &'a CheckedProgram,

    // The function being lowered.
    finished_blocks: Vec<BasicBlock>,
    current_block: BlockId,
    current_insts: Vec<Inst>,
    slots: Vec<SlotInfo>,
    next_vreg: u32,
    next_block: u32,
    // Every local lives in memory: its address and type, per scope.
    scopes: Vec<HashMap<String, (VReg, TypeInternal)>>,
    return_ty: TypeInternal,
    // Hidden pointer to the caller's result slot for compound returns.
    sret: Option<VReg>,
    loops: Vec<LoopTarget>,

    // The whole program.
    strings: Vec<StringConstant>,
    globals: Vec<GlobalData>,
    global_index: HashMap<String, usize>,
}

impl<'a> Lowerer<'a> {
    fn new(checked: &'a CheckedProgram) -> Self {
        Self {
            checked,
            finished_blocks: Vec::new(),
            current_block: BlockId(0),
            current_insts: Vec::new(),
            slots: Vec::new(),
            next_vreg: 0,
            next_block: 0,
            scopes: vec![HashMap::new()],
            return_ty: TypeInternal::Unit,
            sret: None,
            loops: Vec::new(),
            strings: Vec::new(),
            globals: Vec::new(),
            global_index: HashMap::new(),
        }
    }

    // ---- Vregs, slots and blocks ----

    fn fresh_vreg(&mut self) -> VReg {
        let vreg = VReg(self.next_vreg);
        self.next_vreg += 1;
        vreg
    }

    fn fresh_block(&mut self) -> BlockId {
        let block = BlockId(self.next_block);
        self.next_block += 1;
        block
    }

    fn alloc_slot(&mut self, size: u64, align: u64) -> Slot {
        let slot = Slot(self.slots.len() as u32);
        self.slots.push(SlotInfo { size, align });
        slot
    }

    // A fresh stack slot for a value of `ty`, and its address.
    fn alloc_temp(&mut self, ty: &TypeInternal) -> VReg {
        let layout = layout_of(ty, &self.checked.structs);
        let slot = self.alloc_slot(layout.size, layout.align);
        self.slot_addr(slot)
    }

    fn emit(&mut self, inst: Inst) {
        self.current_insts.push(inst);
    }

    // Ends the current block with `term`.
    fn finish_block(&mut self, term: Term) {
        self.finished_blocks.push(BasicBlock {
            id: self.current_block,
            instructions: std::mem::take(&mut self.current_insts),
            terminator: term,
        });
    }

    // Continues emitting into block `id`.
    fn start_block(&mut self, id: BlockId) {
        self.current_block = id;
        self.current_insts = Vec::new();
    }

    // Ends the current block with `term` and continues in a fresh block that
    // nothing jumps to (code after `return`, `break`, ...).
    fn terminate(&mut self, term: Term) {
        self.finish_block(term);
        let dead = self.fresh_block();
        self.start_block(dead);
    }

    // ---- Emitting common instructions ----

    fn slot_addr(&mut self, slot: Slot) -> VReg {
        let addr = self.fresh_vreg();
        self.emit(Inst::SlotAddr(addr, slot));
        addr
    }

    fn load(&mut self, addr: VReg, ty: IRType) -> VReg {
        let value = self.fresh_vreg();
        self.emit(Inst::Load(value, addr, ty));
        value
    }

    fn const_int(&mut self, value: i64, ty: IRType) -> VReg {
        let vreg = self.fresh_vreg();
        self.emit(Inst::ConstInt(vreg, value, ty));
        vreg
    }

    fn member_ptr(&mut self, base: VReg, offset: u64) -> VReg {
        let ptr = self.fresh_vreg();
        self.emit(Inst::MemberPtr(ptr, base, offset));
        ptr
    }

    // The value standing in for () (and the result of code that produces
    // no value).
    fn unit_value(&mut self) -> VReg {
        self.const_int(0, IRType::I8)
    }

    // A placeholder value of type `ty` for code that is never reached.
    fn placeholder(&mut self, ty: &TypeInternal) -> VReg {
        match type_internal_to_ir(ty) {
            Some(ir) if ir.is_float() => {
                let vreg = self.fresh_vreg();
                self.emit(Inst::ConstFloat(vreg, 0.0, ir));
                vreg
            }
            Some(ir) => self.const_int(0, ir),
            None if is_compound(ty) => self.alloc_temp(ty),
            None => self.unit_value(),
        }
    }

    // ---- Scopes ----

    fn push_scope(&mut self) {
        self.scopes.push(HashMap::new());
    }

    fn pop_scope(&mut self) {
        self.scopes.pop();
    }

    fn define(&mut self, name: String, addr: VReg, ty: TypeInternal) {
        self.scopes
            .last_mut()
            .expect("a function body always has a scope")
            .insert(name, (addr, ty));
    }

    fn lookup_local(&self, name: &str) -> Option<&(VReg, TypeInternal)> {
        self.scopes.iter().rev().find_map(|scope| scope.get(name))
    }

    // The storage of a variable or static: its address and type. Constants
    // and functions have none.
    fn variable_place(&mut self, name: &str) -> Option<(VReg, TypeInternal)> {
        if let Some(place) = self.lookup_local(name) {
            return Some(place.clone());
        }
        let index = *self.global_index.get(name)?;
        let addr = self.fresh_vreg();
        self.emit(Inst::GlobalAddr(addr, index));
        Some((addr, self.checked.statics[name].ty.clone()))
    }

    fn is_variable(&self, name: &str) -> bool {
        self.lookup_local(name).is_some() || self.global_index.contains_key(name)
    }

    // ---- Facts from the type checker ----

    // The type the checker gave the expression in its context.
    fn type_of(&self, expr: &Expr) -> TypeInternal {
        self.checked.type_of(expr).clone()
    }

    // Control never continues past the expression.
    fn diverges(&self, expr: &Expr) -> bool {
        self.checked.diverges(expr)
    }

    fn size_of(&self, ty: &TypeInternal) -> u64 {
        layout_of(ty, &self.checked.structs).size
    }
}

pub fn lower(program: &Program, checked: &CheckedProgram) -> IrProgram {
    Lowerer::new(checked).lower_program(program)
}

#[cfg(test)]
mod tests;
