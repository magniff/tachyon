## No VOLE_ROOT (and no main.vl here): a FILE outside the compiler's
## source names its program, the main.vl next to it (0.12).
$ show text/main.vl:21
// crate::quad	text/main.vl:19-22	effects: none
// Four times x.
fn quad(x: i64) -> i64 {
    twice(twice(x))
}
$ def text/util.vl:5
crate::util::half	text/util.vl:5:8	fn	pub fn half(x: i64) -> i64	effects: none
$ show clash/geom.vl:16
// crate::geom::V2::len	clash/geom.vl:14-17	effects: none
    /// Its squared length.
    pub fn len(self) -> i64 {
        self.x * self.x + self.y * self.y
    }
