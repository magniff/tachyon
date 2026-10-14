## No root given, no TACHYON_ROOT, and no main.tach here.
$ def main
error query.no-root: no root (TACHYON_ROOT, ./main.tach, ./compiler/src/main.tach)
try: tachyonc query def main path/to/main.tach
[exit 2]
$ refs
error query.usage: refs needs a NAME (a path or its end: f, m::f, T::f, T.field)
try: tachyonc query items
[exit 2]
$ frobnicate x
error query.usage: unknown command 'frobnicate'
try: tachyonc query def x
[exit 2]
