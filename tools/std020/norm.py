# Compares two vole assembly files across std's reorganization: the
# functions' code only (a sorted multiset of bodies), with std's module
# segments dropped from symbols and string-literal labels made anonymous
# (the string pool and the source-position tables follow std's text,
# which moved). Exit 0 when equal.
import re, sys
MODS = r'(?:fmt|iter|slice|ops|io|num|convert|clone|collections\.hash_map|collections)'
def funcs(path):
    t = open(path, errors='replace').read()
    t = re.sub(r'std\.' + MODS + r'\.', 'std.', t)
    t = re.sub(r'L?\.?Lstr\.\d+', 'Lstr', t)
    # (a type's mangled path is length-prefixed: GN20std.Interp)
    t = re.sub(r'N\d+std\.', 'Nstd.', t)
    out, cur, keep = [], [], False
    for line in t.split('\n'):
        if line.startswith('.section') or line.startswith('\t.section') or line.startswith('.text') or line.startswith('.data'):
            keep = ('__text' in line) or line.startswith('.text') or ('.text' in line)
            continue
        if re.match(r'^_?[A-Za-z_.$][\w.$]*:$', line) and not line.startswith('L'):
            if cur: out.append('\n'.join(cur))
            cur = [line] if keep else []
            continue
        if keep and cur is not None:
            cur.append(line)
    if cur: out.append('\n'.join(cur))
    res = []
    for body in out:
        if not body: continue
        seen = {}
        def lab(m):
            k = m.group(0)
            if k not in seen: seen[k] = 'L%d' % len(seen)
            return seen[k]
        res.append(re.sub(r'\bL\d+\b', lab, body))
    return sorted(res)
a, b = funcs(sys.argv[1]), funcs(sys.argv[2])
if a != b and len(sys.argv) > 3:
    sa, sb = set(a), set(b)
    print([x.split('\n')[0] for x in a if x not in sb][:5], [x.split('\n')[0] for x in b if x not in sa][:5])
sys.exit(0 if a == b else 1)
