#[derive(Debug, Clone, Copy)]
pub struct Float(pub f64);

impl std::fmt::Display for Float {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        write!(f, "{}", self.0)
    }
}

impl PartialEq for Float {
    fn eq(&self, other: &Self) -> bool {
        self.0.to_bits() == other.0.to_bits()
    }
}
impl Eq for Float {}

impl From<f64> for Float {
    fn from(value: f64) -> Self {
        Self(value)
    }
}

impl std::ops::Deref for Float {
    type Target = f64;
    fn deref(&self) -> &Self::Target {
        &self.0
    }
}
