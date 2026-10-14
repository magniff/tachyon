## No TACHYON_ROOT (and no main.tach here): a FILE outside the compiler's
## source names its program, the main.tach next to it (0.12).
$ show text/main.tach:21
// crate::quad	text/main.tach:19-22
// Four times x.
fn quad(x: i64) -> i64 {
    twice(twice(x))
}
$ def text/util.tach:5
crate::util::half	text/util.tach:5:8	fn	pub fn half(x: i64) -> i64
$ show clash/geom.tach:16
// crate::geom::V2::len	clash/geom.tach:14-17
    /// Its squared length.
    pub fn len(self: *V2) -> i64 {
        self.x * self.x + self.y * self.y
    }
