# No root given, no TACHYON_ROOT, and no main.tach here.
$ def main
tachyonc query: no program to ask about: pass its root file (tachyonc query def ... ROOT, e.g. compiler/src/main.tach), set TACHYON_ROOT, or run where ./main.tach or ./compiler/src/main.tach is
[exit 2]
$ refs
usage: tachyonc query def|show|refs|callers NAME [ROOT] [--exact] [--count]
       tachyonc query items [MODULE] [ROOT]
NAME: a path (crate::m::f, std::Vec::push, m::T.field, <T as Trait>::f) or its end (f, T::f, T.field)
ROOT: the program's root file (default: $TACHYON_ROOT, ./main.tach or ./compiler/src/main.tach); see docs/query.md
[exit 2]
$ frobnicate x
usage: tachyonc query def|show|refs|callers NAME [ROOT] [--exact] [--count]
       tachyonc query items [MODULE] [ROOT]
NAME: a path (crate::m::f, std::Vec::push, m::T.field, <T as Trait>::f) or its end (f, T::f, T.field)
ROOT: the program's root file (default: $TACHYON_ROOT, ./main.tach or ./compiler/src/main.tach); see docs/query.md
[exit 2]
