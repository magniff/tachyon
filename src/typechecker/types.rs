// Resolved types.

use std::fmt;

use crate::lexer::token::NumSuffix;

// A type after name resolution: no spans, structs referred to by name.
#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum TypeInternal {
    I8,
    I16,
    I32,
    I64,
    U8,
    U16,
    U32,
    U64,
    F32,
    F64,
    Bool,
    Unit,
    // `!`: the expression never produces a value.
    Never,
    Tuple(Vec<TypeInternal>),
    Array(Box<TypeInternal>, u64),
    Pointer(Box<TypeInternal>),
    Fn {
        params: Vec<TypeInternal>,
        result: Box<TypeInternal>,
    },
    Struct(String),
}

// Writes `items` separated by ", ".
fn write_list(f: &mut fmt::Formatter<'_>, items: &[TypeInternal]) -> fmt::Result {
    for (i, item) in items.iter().enumerate() {
        if i > 0 {
            write!(f, ", ")?;
        }
        write!(f, "{}", item)?;
    }
    Ok(())
}

impl fmt::Display for TypeInternal {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            TypeInternal::Tuple(elems) => {
                write!(f, "(")?;
                write_list(f, elems)?;
                if elems.len() == 1 {
                    write!(f, ",")?;
                }
                write!(f, ")")
            }
            TypeInternal::Array(elem, len) => write!(f, "[{}; {}]", elem, len),
            TypeInternal::Pointer(pointee) => write!(f, "*{}", pointee),
            TypeInternal::Fn { params, result } => {
                write!(f, "fn(")?;
                write_list(f, params)?;
                write!(f, ")")?;
                if **result != TypeInternal::Unit {
                    write!(f, " -> {}", result)?;
                }
                Ok(())
            }
            TypeInternal::Struct(name) => write!(f, "{}", name),
            TypeInternal::Unit => write!(f, "()"),
            TypeInternal::Never => write!(f, "!"),
            scalar => write!(f, "{}", scalar.scalar_name()),
        }
    }
}

impl TypeInternal {
    pub fn is_integer(&self) -> bool {
        matches!(
            self,
            TypeInternal::I8
                | TypeInternal::I16
                | TypeInternal::I32
                | TypeInternal::I64
                | TypeInternal::U8
                | TypeInternal::U16
                | TypeInternal::U32
                | TypeInternal::U64
        )
    }

    pub fn is_signed(&self) -> bool {
        matches!(
            self,
            TypeInternal::I8 | TypeInternal::I16 | TypeInternal::I32 | TypeInternal::I64
        )
    }

    pub fn is_float(&self) -> bool {
        matches!(self, TypeInternal::F32 | TypeInternal::F64)
    }

    pub fn is_numeric(&self) -> bool {
        self.is_integer() || self.is_float()
    }

    pub fn is_pointer(&self) -> bool {
        matches!(self, TypeInternal::Pointer(_))
    }

    // Width in bits of an integer, pointer or bool.
    pub(super) fn int_bits(&self) -> u32 {
        match self {
            TypeInternal::I8 | TypeInternal::U8 | TypeInternal::Bool => 8,
            TypeInternal::I16 | TypeInternal::U16 => 16,
            TypeInternal::I32 | TypeInternal::U32 => 32,
            _ => 64,
        }
    }

    // The name of a primitive type, as written in source.
    fn scalar_name(&self) -> &'static str {
        match self {
            TypeInternal::I8 => "i8",
            TypeInternal::I16 => "i16",
            TypeInternal::I32 => "i32",
            TypeInternal::I64 => "i64",
            TypeInternal::U8 => "u8",
            TypeInternal::U16 => "u16",
            TypeInternal::U32 => "u32",
            TypeInternal::U64 => "u64",
            TypeInternal::F32 => "f32",
            TypeInternal::F64 => "f64",
            TypeInternal::Bool => "bool",
            _ => unreachable!("'{:?}' is not a primitive type", self),
        }
    }

    // The largest value a literal of this integer type may have.
    pub(super) fn int_max(&self) -> Option<u64> {
        Some(match self {
            TypeInternal::U8 => u8::MAX as u64,
            TypeInternal::U16 => u16::MAX as u64,
            TypeInternal::U32 => u32::MAX as u64,
            TypeInternal::U64 => u64::MAX,
            TypeInternal::I8 => i8::MAX as u64,
            TypeInternal::I16 => i16::MAX as u64,
            TypeInternal::I32 => i32::MAX as u64,
            TypeInternal::I64 => i64::MAX as u64,
            _ => return None,
        })
    }

    // The type of a pointer to this type.
    pub(super) fn pointer_to(self) -> TypeInternal {
        TypeInternal::Pointer(Box::new(self))
    }
}

// The type named by a literal suffix (`1u8`, `2.5f32`).
pub(super) fn suffix_type(suffix: NumSuffix) -> TypeInternal {
    match suffix {
        NumSuffix::I8 => TypeInternal::I8,
        NumSuffix::I16 => TypeInternal::I16,
        NumSuffix::I32 => TypeInternal::I32,
        NumSuffix::I64 | NumSuffix::Isize => TypeInternal::I64,
        NumSuffix::U8 => TypeInternal::U8,
        NumSuffix::U16 => TypeInternal::U16,
        NumSuffix::U32 => TypeInternal::U32,
        NumSuffix::U64 | NumSuffix::Usize => TypeInternal::U64,
        NumSuffix::F32 => TypeInternal::F32,
        NumSuffix::F64 => TypeInternal::F64,
    }
}

pub(super) fn primitive_type(name: &str) -> Option<TypeInternal> {
    Some(match name {
        "i8" => TypeInternal::I8,
        "i16" => TypeInternal::I16,
        "i32" => TypeInternal::I32,
        "i64" | "isize" => TypeInternal::I64,
        "u8" => TypeInternal::U8,
        "u16" => TypeInternal::U16,
        "u32" => TypeInternal::U32,
        "u64" | "usize" => TypeInternal::U64,
        "f32" => TypeInternal::F32,
        "f64" => TypeInternal::F64,
        "bool" => TypeInternal::Bool,
        _ => return None,
    })
}

// A string literal's type: a (pointer, length) pair.
pub(super) fn string_type() -> TypeInternal {
    TypeInternal::Tuple(vec![TypeInternal::U8.pointer_to(), TypeInternal::U64])
}
