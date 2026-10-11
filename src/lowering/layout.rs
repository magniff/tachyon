// Memory layout of tachyon types, and their IR representation.

use std::collections::HashMap;

use super::IRType;
use crate::typechecker::{StructInfo, TypeInternal};

// Size of a pointer (and of `fn` values) on every supported target.
pub const POINTER_SIZE: u64 = 8;

#[derive(Debug, Clone, Copy)]
pub struct Layout {
    pub size: u64,
    pub align: u64,
}

impl Layout {
    const fn scalar(size: u64) -> Layout {
        Layout { size, align: size }
    }
}

fn align_to(offset: u64, align: u64) -> u64 {
    (offset + align - 1) & !(align - 1)
}

pub fn layout_of(ty: &TypeInternal, structs: &HashMap<String, StructInfo>) -> Layout {
    match ty {
        TypeInternal::I8 | TypeInternal::U8 | TypeInternal::Bool => Layout::scalar(1),
        TypeInternal::I16 | TypeInternal::U16 => Layout::scalar(2),
        TypeInternal::I32 | TypeInternal::U32 | TypeInternal::F32 => Layout::scalar(4),
        TypeInternal::I64 | TypeInternal::U64 | TypeInternal::F64 => Layout::scalar(8),
        TypeInternal::Pointer(_) | TypeInternal::Fn { .. } => Layout::scalar(POINTER_SIZE),
        TypeInternal::Unit | TypeInternal::Never => Layout { size: 0, align: 1 },
        TypeInternal::Tuple(elems) => compound_layout(elems.iter(), structs),
        TypeInternal::Array(elem, len) => {
            let elem_layout = layout_of(elem, structs);
            Layout {
                size: elem_layout.size * len,
                align: elem_layout.align,
            }
        }
        TypeInternal::Struct(name) => {
            let info = &structs[name];
            compound_layout(info.fields.iter().map(|(_, ty)| ty), structs)
        }
    }
}

// C layout: each field at the next offset aligned for it, the whole padded
// to its largest alignment.
fn compound_layout<'a>(
    fields: impl Iterator<Item = &'a TypeInternal>,
    structs: &HashMap<String, StructInfo>,
) -> Layout {
    let mut offset: u64 = 0;
    let mut max_align: u64 = 1;
    for field_ty in fields {
        let field_layout = layout_of(field_ty, structs);
        max_align = max_align.max(field_layout.align);
        offset = align_to(offset, field_layout.align) + field_layout.size;
    }
    Layout {
        size: align_to(offset, max_align),
        align: max_align,
    }
}

// The offset and layout of each field of a tuple or struct.
pub fn field_offsets(
    fields: &[TypeInternal],
    structs: &HashMap<String, StructInfo>,
) -> Vec<(u64, Layout)> {
    let mut offset: u64 = 0;
    let mut result = Vec::new();
    for field_ty in fields {
        let field_layout = layout_of(field_ty, structs);
        offset = align_to(offset, field_layout.align);
        result.push((offset, field_layout));
        offset += field_layout.size;
    }
    result
}

// The IR type of a scalar; None for (), `!` and compound types.
pub fn type_internal_to_ir(ty: &TypeInternal) -> Option<IRType> {
    match ty {
        TypeInternal::I8 | TypeInternal::U8 | TypeInternal::Bool => Some(IRType::I8),
        TypeInternal::I16 | TypeInternal::U16 => Some(IRType::I16),
        TypeInternal::I32 | TypeInternal::U32 => Some(IRType::I32),
        TypeInternal::I64 | TypeInternal::U64 => Some(IRType::I64),
        TypeInternal::F32 => Some(IRType::F32),
        TypeInternal::F64 => Some(IRType::F64),
        TypeInternal::Pointer(_) | TypeInternal::Fn { .. } => Some(IRType::Ptr),
        _ => None,
    }
}

// The IR type of a type known to be scalar.
pub(super) fn scalar_ir(ty: &TypeInternal) -> IRType {
    type_internal_to_ir(ty).unwrap_or_else(|| panic!("ICE: '{}' is not a scalar type", ty))
}

// Held in a vreg.
pub(super) fn is_scalar(ty: &TypeInternal) -> bool {
    type_internal_to_ir(ty).is_some()
}

// Held in memory; a vreg holds its address.
pub(super) fn is_compound(ty: &TypeInternal) -> bool {
    matches!(
        ty,
        TypeInternal::Struct(_) | TypeInternal::Tuple(_) | TypeInternal::Array(_, _)
    )
}

// Types without a runtime value.
pub(super) fn is_void(ty: &TypeInternal) -> bool {
    matches!(ty, TypeInternal::Unit | TypeInternal::Never)
}
