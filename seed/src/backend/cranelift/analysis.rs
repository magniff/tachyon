// Facts about vregs: which instruction defines each, which read them, and
// their types.

use std::collections::HashMap;

use crate::lowering::{IRFunction, IRType, Inst, Term, VReg};

// The vreg an instruction defines, if any, and its type (None for a `Mov`,
// which takes the type of its source).
pub(super) fn inst_def(inst: &Inst) -> Option<(VReg, Option<IRType>)> {
    use Inst::*;
    Some(match inst {
        IAdd(d, _, _, t)
        | ISub(d, _, _, t)
        | IMul(d, _, _, t)
        | IDiv(d, _, _, t, _)
        | IMod(d, _, _, t, _)
        | IShl(d, _, _, t)
        | IShr(d, _, _, t, _)
        | IBitAnd(d, _, _, t)
        | IBitOr(d, _, _, t)
        | IBitXor(d, _, _, t)
        | FAdd(d, _, _, t)
        | FSub(d, _, _, t)
        | FMul(d, _, _, t)
        | FDiv(d, _, _, t) => (*d, Some(*t)),
        INeg(d, _, t) | IBitNot(d, _, t) | FNeg(d, _, t) => (*d, Some(*t)),
        ICmp(d, ..) | FCmp(d, ..) | BoolNot(d, _) => (*d, Some(IRType::I8)),
        ConstInt(d, _, t) | ConstFloat(d, _, t) => (*d, Some(*t)),
        ConstStringPtr(d, _)
        | GlobalAddr(d, _)
        | SlotAddr(d, _)
        | MemberPtr(d, _, _)
        | IndexPtr(d, _, _, _)
        | FuncAddr(d, _) => (*d, Some(IRType::Ptr)),
        IntToFloat(d, _, _, t, _)
        | FloatToInt(d, _, _, t, _)
        | FloatToFloat(d, _, _, t)
        | IntExt(d, _, _, t, _)
        | IntTrunc(d, _, _, t) => (*d, Some(*t)),
        Load(d, _, t) => (*d, Some(*t)),
        Call { dst, .. } | CallIndirect { dst, .. } => {
            let (dst, ty) = (*dst)?;
            (dst, Some(ty))
        }
        Mov(d, _) => (*d, None),
        Store(..) | MemCopy { .. } => return None,
    })
}

// Every vreg an instruction reads.
pub(super) fn inst_uses(inst: &Inst) -> Vec<VReg> {
    use Inst::*;
    match inst {
        IAdd(_, a, b, _)
        | ISub(_, a, b, _)
        | IMul(_, a, b, _)
        | IDiv(_, a, b, _, _)
        | IMod(_, a, b, _, _)
        | IShl(_, a, b, _)
        | IShr(_, a, b, _, _)
        | IBitAnd(_, a, b, _)
        | IBitOr(_, a, b, _)
        | IBitXor(_, a, b, _)
        | FAdd(_, a, b, _)
        | FSub(_, a, b, _)
        | FMul(_, a, b, _)
        | FDiv(_, a, b, _)
        | ICmp(_, _, a, b, _, _)
        | FCmp(_, _, a, b, _)
        | IndexPtr(_, a, b, _)
        | Store(a, b, _) => vec![*a, *b],
        INeg(_, a, _)
        | IBitNot(_, a, _)
        | FNeg(_, a, _)
        | BoolNot(_, a)
        | IntToFloat(_, a, _, _, _)
        | FloatToInt(_, a, _, _, _)
        | FloatToFloat(_, a, _, _)
        | IntExt(_, a, _, _, _)
        | IntTrunc(_, a, _, _)
        | Load(_, a, _)
        | MemberPtr(_, a, _)
        | Mov(_, a) => vec![*a],
        MemCopy { dst, src, .. } => vec![*dst, *src],
        Call { args, .. } => args.iter().map(|(v, _)| *v).collect(),
        CallIndirect { callee, args, .. } => {
            let mut uses = vec![*callee];
            uses.extend(args.iter().map(|(v, _)| *v));
            uses
        }
        ConstInt(..) | ConstFloat(..) | ConstStringPtr(..) | GlobalAddr(..) | SlotAddr(..)
        | FuncAddr(..) => vec![],
    }
}

pub(super) fn term_uses(term: &Term) -> Vec<VReg> {
    match term {
        Term::Ret(Some((v, _))) => vec![*v],
        Term::CondBr { cond, .. } => vec![*cond],
        Term::Ret(None) | Term::Jump(_) => vec![],
    }
}

// The type of every vreg, from its (first) definition. A `Mov` takes its
// source's type, so the walk repeats until nothing changes.
pub(super) fn vreg_types(function: &IRFunction) -> HashMap<u32, IRType> {
    let mut types: HashMap<u32, IRType> = HashMap::new();
    for (vreg, ty) in &function.params {
        types.insert(vreg.0, *ty);
    }
    let insts = || function.blocks.iter().flat_map(|block| &block.instructions);
    loop {
        let mut changed = false;
        for inst in insts() {
            let Some((dst, ty)) = inst_def(inst) else {
                continue;
            };
            if types.contains_key(&dst.0) {
                continue;
            }
            let ty = match (ty, inst) {
                (Some(ty), _) => Some(ty),
                (None, Inst::Mov(_, src)) => types.get(&src.0).copied(),
                _ => None,
            };
            if let Some(ty) = ty {
                types.insert(dst.0, ty);
                changed = true;
            }
        }
        if !changed {
            return types;
        }
    }
}
