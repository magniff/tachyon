// Translation of one IR function to CLIF.

use std::collections::{HashMap, HashSet};

use cranelift_codegen::ir::{
    self, InstBuilder, MemFlagsData, StackSlotData, StackSlotKind, Type, types,
};
use cranelift_frontend::{FunctionBuilder, FunctionBuilderContext, Variable};
use cranelift_module::{DataId, FuncId, Module};

use super::analysis::vreg_types;
use super::codegen::Codegen;
use super::error;
use super::mem2reg::promotable_slots;
use crate::backend::GeneratorError;
use crate::lowering::{BlockId, IRFunction, IRType, SlotInfo, Term, VReg};

// Explicit stack slots are aligned to at most this many bytes.
const MAX_STACK_SLOT_ALIGN: u64 = 16;

// The trap code for blocks that can never be reached.
const UNREACHABLE_TRAP: u8 = 1;

pub(super) fn mem_flags() -> MemFlagsData {
    MemFlagsData::new()
}

pub(super) struct Translator<'a> {
    pub builder: FunctionBuilder<'a>,
    pub codegen: &'a mut Codegen,
    // The function's declared return type.
    return_type: Option<IRType>,
    blocks: HashMap<u32, ir::Block>,
    variables: HashMap<u32, Variable>,
    vreg_types: HashMap<u32, IRType>,
    // Address vreg of a promoted slot -> the slot's variable.
    pub promoted: HashMap<u32, Variable>,
    pub stack_slots: HashMap<u32, ir::StackSlot>,
    func_refs: HashMap<FuncId, ir::FuncRef>,
    data_refs: HashMap<DataId, ir::GlobalValue>,
    // Set when the function uses something this backend cannot express.
    pub unsupported: Option<String>,
}

impl<'a> Translator<'a> {
    pub fn new(
        codegen: &'a mut Codegen,
        func: &'a mut ir::Function,
        builder_context: &'a mut FunctionBuilderContext,
        return_type: Option<IRType>,
    ) -> Translator<'a> {
        Translator {
            builder: FunctionBuilder::new(func, builder_context),
            codegen,
            return_type,
            blocks: HashMap::new(),
            variables: HashMap::new(),
            vreg_types: HashMap::new(),
            promoted: HashMap::new(),
            stack_slots: HashMap::new(),
            func_refs: HashMap::new(),
            data_refs: HashMap::new(),
            unsupported: None,
        }
    }

    pub fn translate(mut self, function: &IRFunction) -> Result<(), GeneratorError> {
        self.vreg_types = vreg_types(function);
        let promotable = promotable_slots(function);
        self.create_stack_slots(&function.slots, &promotable);
        self.declare_promoted_variables(&promotable);
        self.translate_entry(function);

        let mut translated: HashSet<u32> = HashSet::new();
        for block in &function.blocks {
            let clif_block = self.block(block.id);
            translated.insert(block.id.0);
            self.builder.switch_to_block(clif_block);
            for inst in &block.instructions {
                self.inst(inst);
            }
            self.term(&block.terminator);
        }
        self.trap_in_untranslated_blocks(&translated);

        self.builder.seal_all_blocks();
        let config = self.codegen.module.target_config();
        self.builder.finalize(config);
        match self.unsupported {
            Some(message) => Err(error(format!("{}: {}", function.name, message))),
            None => Ok(()),
        }
    }

    // An explicit stack slot for every slot that is not promoted.
    fn create_stack_slots(&mut self, slots: &[SlotInfo], promotable: &HashMap<u32, (u32, IRType)>) {
        for (index, slot) in slots.iter().enumerate() {
            let index = index as u32;
            if promotable.values().any(|(promoted, _)| *promoted == index) {
                continue;
            }
            let align = slot.align.clamp(1, MAX_STACK_SLOT_ALIGN);
            let data = StackSlotData::new(
                StackSlotKind::ExplicitSlot,
                slot.size.max(1) as u32,
                align.trailing_zeros() as u8,
            );
            let stack_slot = self.builder.create_sized_stack_slot(data);
            self.stack_slots.insert(index, stack_slot);
        }
    }

    // One variable per promoted slot, shared by all of its address vregs.
    fn declare_promoted_variables(&mut self, promotable: &HashMap<u32, (u32, IRType)>) {
        let mut slot_variables: HashMap<u32, Variable> = HashMap::new();
        for (addr, (slot, ty)) in promotable {
            let variable = *slot_variables.entry(*slot).or_insert_with(|| {
                self.builder
                    .declare_var(super::codegen::clif_type(*ty, self.codegen.pointer_type))
            });
            self.promoted.insert(*addr, variable);
        }
    }

    // The CLIF entry block binds the parameters, then jumps to the IR's
    // first block (which may be a loop header).
    fn translate_entry(&mut self, function: &IRFunction) {
        let entry = self.builder.create_block();
        self.builder.append_block_params_for_function_params(entry);
        self.builder.switch_to_block(entry);
        let params: Vec<ir::Value> = self.builder.block_params(entry).to_vec();
        for ((vreg, _), value) in function.params.iter().zip(params) {
            self.def_vreg(*vreg, value);
        }
        let first = self.block(BlockId(0));
        self.builder.ins().jump(first, &[]);
    }

    // Branch targets the lowering never filled in cannot be reached.
    fn trap_in_untranslated_blocks(&mut self, translated: &HashSet<u32>) {
        let untranslated: Vec<ir::Block> = self
            .blocks
            .iter()
            .filter(|(id, _)| !translated.contains(id))
            .map(|(_, block)| *block)
            .collect();
        for block in untranslated {
            self.builder.switch_to_block(block);
            self.trap();
        }
    }

    pub fn trap(&mut self) {
        self.builder
            .ins()
            .trap(ir::TrapCode::unwrap_user(UNREACHABLE_TRAP));
    }

    fn term(&mut self, term: &Term) {
        match term {
            Term::Ret(value) => {
                let return_type = self.return_type.map(|ty| self.clif_type(ty));
                match (return_type, value) {
                    (Some(ty), Some((vreg, _))) => {
                        let value = self.use_vreg_as(*vreg, ty);
                        self.builder.ins().return_(&[value]);
                    }
                    (Some(ty), None) => {
                        let value = self.zero(ty);
                        self.builder.ins().return_(&[value]);
                    }
                    (None, _) => {
                        self.builder.ins().return_(&[]);
                    }
                }
            }
            Term::Jump(target) => {
                let block = self.block(*target);
                self.builder.ins().jump(block, &[]);
            }
            Term::CondBr {
                cond,
                then_bb,
                else_bb,
            } => {
                // Booleans are bytes; only the low byte is meaningful.
                let cond = self.use_vreg_as(*cond, types::I8);
                let then_block = self.block(*then_bb);
                let else_block = self.block(*else_bb);
                self.builder
                    .ins()
                    .brif(cond, then_block, &[], else_block, &[]);
            }
        }
    }

    // ---- Blocks, variables and values ----

    pub fn clif_type(&self, ty: IRType) -> Type {
        self.codegen.clif_type(ty)
    }

    pub fn pointer_type(&self) -> Type {
        self.codegen.pointer_type
    }

    // The CLIF block of an IR block, created on first use.
    fn block(&mut self, id: BlockId) -> ir::Block {
        if let Some(block) = self.blocks.get(&id.0) {
            return *block;
        }
        let block = self.builder.create_block();
        self.blocks.insert(id.0, block);
        block
    }

    fn vreg_clif_type(&self, vreg: VReg) -> Type {
        let ty = self.vreg_types.get(&vreg.0).copied().unwrap_or(IRType::I64);
        self.clif_type(ty)
    }

    // The variable of a vreg, declared on first use.
    fn variable(&mut self, vreg: VReg) -> Variable {
        if let Some(variable) = self.variables.get(&vreg.0) {
            return *variable;
        }
        let ty = self.vreg_clif_type(vreg);
        let variable = self.builder.declare_var(ty);
        self.variables.insert(vreg.0, variable);
        variable
    }

    pub fn use_vreg(&mut self, vreg: VReg) -> ir::Value {
        let variable = self.variable(vreg);
        self.builder.use_var(variable)
    }

    // The vreg's value as a `ty`.
    pub fn use_vreg_as(&mut self, vreg: VReg, ty: Type) -> ir::Value {
        let value = self.use_vreg(vreg);
        self.coerce(value, ty)
    }

    pub fn def_vreg(&mut self, vreg: VReg, value: ir::Value) {
        let variable = self.variable(vreg);
        let ty = self.vreg_clif_type(vreg);
        let value = self.coerce(value, ty);
        self.builder.def_var(variable, value);
    }

    // Reinterpret a value at another width or class. The IR treats vregs as
    // 64-bit values whose low bytes are read, so narrowing is a truncation
    // and widening a zero-extension.
    pub fn coerce(&mut self, value: ir::Value, to: Type) -> ir::Value {
        let from = self.builder.func.dfg.value_type(value);
        if from == to {
            return value;
        }
        if from.is_int() && to.is_int() {
            if from.bits() > to.bits() {
                self.builder.ins().ireduce(to, value)
            } else {
                self.builder.ins().uextend(to, value)
            }
        } else if from.bits() == to.bits() {
            self.builder.ins().bitcast(to, mem_flags(), value)
        } else if from.is_float() && to.is_int() {
            let bits = Type::int(from.bits() as u16).expect("floats are 32 or 64 bits wide");
            let raw = self.builder.ins().bitcast(bits, mem_flags(), value);
            self.coerce(raw, to)
        } else {
            let bits = Type::int(to.bits() as u16).expect("floats are 32 or 64 bits wide");
            let raw = self.coerce(value, bits);
            self.builder.ins().bitcast(to, mem_flags(), raw)
        }
    }

    // An integer constant, masked to the type's width.
    pub fn iconst(&mut self, ty: Type, value: i64) -> ir::Value {
        let masked = if ty.bits() < 64 {
            value & ((1i64 << ty.bits()) - 1)
        } else {
            value
        };
        self.builder.ins().iconst(ty, masked)
    }

    pub fn zero(&mut self, ty: Type) -> ir::Value {
        if ty == types::F32 {
            self.builder.ins().f32const(0.0)
        } else if ty == types::F64 {
            self.builder.ins().f64const(0.0)
        } else {
            self.builder.ins().iconst(ty, 0)
        }
    }

    pub fn func_ref(&mut self, id: FuncId) -> ir::FuncRef {
        if let Some(func_ref) = self.func_refs.get(&id) {
            return *func_ref;
        }
        let func_ref = self
            .codegen
            .module
            .declare_func_in_func(id, self.builder.func);
        self.func_refs.insert(id, func_ref);
        func_ref
    }

    pub fn data_ref(&mut self, id: DataId) -> ir::GlobalValue {
        if let Some(data_ref) = self.data_refs.get(&id) {
            return *data_ref;
        }
        let data_ref = self
            .codegen
            .module
            .declare_data_in_func(id, self.builder.func);
        self.data_refs.insert(id, data_ref);
        data_ref
    }
}
