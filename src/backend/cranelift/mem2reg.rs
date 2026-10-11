// mem2reg: which stack slots can live in a variable instead of memory.

use std::collections::{HashMap, HashSet};

use super::analysis::{inst_def, inst_uses, term_uses};
use crate::lowering::{IRFunction, IRType, Inst};

// A slot qualifies when each of its address vregs is defined once, by its
// SlotAddr, and is used only as the address of whole-slot loads and stores
// of a single scalar type. Returns address vreg -> (slot, type).
pub(super) fn promotable_slots(function: &IRFunction) -> HashMap<u32, (u32, IRType)> {
    let slot_of = slot_addresses(function);
    let mut escaped = escaping_slots(function, &slot_of);
    let definitions = definition_counts(function);
    for (vreg, slot) in &slot_of {
        if definitions.get(vreg).copied().unwrap_or(0) != 1 {
            escaped.insert(*slot);
        }
    }
    let access = SlotAccess::of(function, &slot_of, &mut escaped);

    slot_of
        .iter()
        .filter_map(|(vreg, slot)| {
            let ty = *access.types.get(slot)?;
            let size = function.slots[*slot as usize].size;
            (!escaped.contains(slot) && ty.size() == size).then_some((*vreg, (*slot, ty)))
        })
        .collect()
}

// The slot whose address each SlotAddr vreg holds.
fn slot_addresses(function: &IRFunction) -> HashMap<u32, u32> {
    let mut slot_of = HashMap::new();
    for block in &function.blocks {
        for inst in &block.instructions {
            if let Inst::SlotAddr(addr, slot) = inst {
                slot_of.insert(addr.0, slot.0);
            }
        }
    }
    slot_of
}

// How many times each vreg is defined (parameters included).
fn definition_counts(function: &IRFunction) -> HashMap<u32, usize> {
    let mut counts: HashMap<u32, usize> = HashMap::new();
    for block in &function.blocks {
        for inst in &block.instructions {
            if let Some((dst, _)) = inst_def(inst) {
                *counts.entry(dst.0).or_default() += 1;
            }
        }
    }
    for (vreg, _) in &function.params {
        *counts.entry(vreg.0).or_default() += 1;
    }
    counts
}

// Slots whose address is used other than as the address of a load or store
// (passed to a call, stored as a value, offset, returned, ...).
fn escaping_slots(function: &IRFunction, slot_of: &HashMap<u32, u32>) -> HashSet<u32> {
    let mut escaped = HashSet::new();
    for block in &function.blocks {
        for inst in &block.instructions {
            let mut uses = inst_uses(inst);
            match inst {
                Inst::Load(_, addr, _) if slot_of.contains_key(&addr.0) => uses.clear(),
                // The stored value may itself be a slot address.
                Inst::Store(addr, _, _) if slot_of.contains_key(&addr.0) => {
                    uses.remove(0);
                }
                _ => {}
            }
            escaped.extend(uses.iter().filter_map(|vreg| slot_of.get(&vreg.0)));
        }
        escaped.extend(
            term_uses(&block.terminator)
                .iter()
                .filter_map(|vreg| slot_of.get(&vreg.0)),
        );
    }
    escaped
}

// The one scalar type each slot is loaded and stored as.
struct SlotAccess {
    types: HashMap<u32, IRType>,
}

impl SlotAccess {
    // Slots accessed as more than one type are added to `escaped`.
    fn of(
        function: &IRFunction,
        slot_of: &HashMap<u32, u32>,
        escaped: &mut HashSet<u32>,
    ) -> SlotAccess {
        let mut types: HashMap<u32, IRType> = HashMap::new();
        for inst in function.blocks.iter().flat_map(|block| &block.instructions) {
            let (addr, ty) = match inst {
                Inst::Load(_, addr, ty) | Inst::Store(addr, _, ty) => (addr, *ty),
                _ => continue,
            };
            let Some(slot) = slot_of.get(&addr.0) else {
                continue;
            };
            match types.get(slot) {
                Some(seen) if *seen != ty => {
                    escaped.insert(*slot);
                }
                Some(_) => {}
                None => {
                    types.insert(*slot, ty);
                }
            }
        }
        SlotAccess { types }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::lowering::{BasicBlock, BlockId, Slot, SlotInfo, Term, VReg};

    fn function(slots: usize, instructions: Vec<Inst>) -> IRFunction {
        IRFunction {
            name: "f".into(),
            params: vec![],
            return_type: None,
            slots: (0..slots).map(|_| SlotInfo { size: 8, align: 8 }).collect(),
            blocks: vec![BasicBlock {
                id: BlockId(0),
                instructions,
                terminator: Term::Ret(None),
            }],
            vreg_count: 16,
            is_extern: false,
            is_variadic: false,
        }
    }

    #[test]
    fn promotes_whole_slot_scalar_access() {
        let f = function(
            1,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::ConstInt(VReg(1), 5, IRType::I64),
                Inst::Store(VReg(0), VReg(1), IRType::I64),
                Inst::Load(VReg(2), VReg(0), IRType::I64),
            ],
        );
        assert_eq!(promotable_slots(&f).get(&0), Some(&(0, IRType::I64)));
    }

    #[test]
    fn escaping_address_is_not_promoted() {
        let f = function(
            1,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::Call {
                    dst: None,
                    func: "g".into(),
                    args: vec![(VReg(0), IRType::Ptr)],
                },
                Inst::Load(VReg(1), VReg(0), IRType::I64),
            ],
        );
        assert!(promotable_slots(&f).is_empty());
    }

    #[test]
    fn address_stored_as_a_value_escapes() {
        let f = function(
            2,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::SlotAddr(VReg(1), Slot(1)),
                Inst::Store(VReg(1), VReg(0), IRType::Ptr),
            ],
        );
        let promoted = promotable_slots(&f);
        assert!(!promoted.contains_key(&0), "slot 0's address escapes");
        assert!(promoted.contains_key(&1), "slot 1 only holds a value");
    }

    #[test]
    fn partial_or_mixed_access_is_not_promoted() {
        let f = function(
            2,
            vec![
                Inst::SlotAddr(VReg(0), Slot(0)),
                Inst::Load(VReg(1), VReg(0), IRType::I32),
                Inst::SlotAddr(VReg(2), Slot(1)),
                Inst::Load(VReg(3), VReg(2), IRType::I64),
                Inst::Load(VReg(4), VReg(2), IRType::F64),
                Inst::MemberPtr(VReg(5), VReg(2), 0),
            ],
        );
        assert!(promotable_slots(&f).is_empty());
    }
}
