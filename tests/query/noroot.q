## No root given, no VOLE_ROOT, and no main.vl here.
$ def main
error query.no-root: no root (VOLE_ROOT, ./main.vl, ./compiler/src/main.vl)
try: volec query def main path/to/main.vl
[exit 2]
$ refs
error query.usage: refs needs a NAME (a path or its end: f, m::f, T::f, T.field; or FILE:LINE)
try: volec query items
[exit 2]
$ frobnicate x
error query.usage: unknown command 'frobnicate'
try: volec query def x
[exit 2]
