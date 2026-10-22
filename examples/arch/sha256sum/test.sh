#!/bin/sh
# The checks of sha256sum, run by the README's session (and so by
# tests/walkthrough/run.sh on every build): ./sha256sum and
# ./sha256sum-generic (-C target-cpu=generic, where detect("sha2") is a
# real test, so VOLE_ARCH_DISABLE=all reaches the portable rounds)
# must be built. Prints one line per check; FAIL lines say what differed.
set -u
LC_ALL=C
export LC_ALL
fails=0
fail() {
    echo "FAIL: $*"
    fails=$((fails + 1))
}
here=$(pwd)
fast="$here/sha256sum"
generic="$here/sha256sum-generic"
work=$(mktemp -d "${TMPDIR:-/tmp}/sha256sum-test.XXXXXX")
trap 'rm -rf "$work"' EXIT
cd "$work" || exit 1

# The system's tool, to compare with: coreutils, macOS's, perl's, openssl.
sys=
for t in sha256sum /sbin/sha256sum gsha256sum; do
    if command -v "$t" >/dev/null 2>&1; then sys=$t; break; fi
done
if [ -z "$sys" ] && command -v shasum >/dev/null 2>&1; then sys="shasum -a 256"; fi
if [ -z "$sys" ] && command -v openssl >/dev/null 2>&1; then sys="openssl dgst -sha256 -r"; fi
[ -n "$sys" ] || fail "no system SHA-256 tool to compare with"

# n random bytes into a file (macOS's head refuses -c 0).
random_file() {
    if [ "$1" = 0 ]; then : >"$2"; else head -c "$1" /dev/urandom >"$2"; fi
}

# The hashes alone, one a line, of a tool's output.
hashes() { sed 's/^\\//' | cut -c1-64; }

# 1. FIPS 180-4's examples and the million a's: the known answers, by
# both paths.
known() { # text expected
    for p in "$fast" "VOLE_ARCH_DISABLE=all $generic"; do
        got=$(printf '%s' "$1" | env $p | cut -c1-64)
        [ "$got" = "$2" ] || fail "'$1' by $p: $got, expected $2"
    done
}
known "" e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
known abc ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
known abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq \
    248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1
known abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu \
    cf5b16a778af8380036ce59e7b0492370b249b11e8f07a51afac45037afee9d1
head -c 1000000 /dev/zero | tr '\0' a >million
for p in "$fast" "VOLE_ARCH_DISABLE=all $generic"; do
    got=$(env $p million | cut -c1-64)
    [ "$got" = cdc76e5c9914fb9281a1c7e284d73e67f1809a48a497200e046d39ccc7112cd0 ] \
        || fail "a million a's by $p: $got"
done
echo "known answers: 5 messages, both paths"

# 2. The lengths around the padding's and the read buffer's edges, as
# files and through a pipe in 37-byte writes (each read's leftover bytes
# carried to the next).
lengths="0 1 55 56 63 64 65 119 120 1048575 1048576 1048577"
for n in $lengths; do
    random_file "$n" "len$n"
done
names=$(for n in $lengths; do printf 'len%s ' "$n"; done)
# shellcheck disable=SC2086
$sys $names | hashes >want
# shellcheck disable=SC2086
"$fast" $names | hashes >got
cmp -s want got || fail "lengths: not the system's hashes"
# shellcheck disable=SC2086
VOLE_ARCH_DISABLE=all "$generic" $names | hashes >got
cmp -s want got || fail "lengths, portable: not the system's hashes"
for n in $lengths; do
    dd if="len$n" bs=37 2>/dev/null | "$fast" | hashes
done >got
cmp -s want got || fail "lengths through a pipe: not the system's hashes"
echo "lengths: 12, as files and through a pipe, the system's hashes"

# 3. Random files of random lengths: the system's hashes, by both paths.
i=0
while [ $i -lt 40 ]; do
    n=$(od -An -N3 -tu4 /dev/urandom | tr -d ' ')
    random_file $((n % 300000)) "r$i"
    i=$((i + 1))
done
$sys r* | hashes >want
"$fast" r* | hashes >got
cmp -s want got || fail "random files: not the system's hashes"
"$generic" r* | hashes >got
cmp -s want got || fail "random files, -C target-cpu=generic: not the system's hashes"
VOLE_ARCH_DISABLE=all "$generic" r* | hashes >got
cmp -s want got || fail "random files, portable: not the system's hashes"
echo "random files: 40, by both paths, the system's hashes"

# 4. -c: what sha256sum writes, it checks; and the other formats.
"$fast" r* len* >sums
"$fast" -c --quiet sums || fail "-c of its own list"
"$fast" --tag r* >tagged
"$fast" -c --quiet tagged || fail "-c of a --tag list"
"$fast" -b r1 >binary
"$fast" -c --quiet binary || fail "-c of a -b list"
case "$sys" in
    *sha256sum)
        $sys -c --quiet sums || fail "the system's -c of sha256sum's list"
        $sys r* >theirs
        "$fast" -c --quiet theirs || fail "-c of the system's list"
        ;;
esac
printf 'x' >>r0
"$fast" -c --quiet sums >out 2>err
rc=$?
[ $rc = 1 ] || fail "-c with a changed file: exit $rc"
grep -qx 'r0: FAILED' out || fail "-c with a changed file: $(cat out)"
grep -qx 'sha256sum: WARNING: 1 computed checksum did NOT match' err \
    || fail "-c with a changed file: $(cat err)"
echo "-c: its own lists (plain, --tag, -b) and the system's"

# 5. Names with a backslash or a newline: escaped, and read back.
printf 'abc' >'back\slash'
printf 'abc' >'new
line'
"$fast" 'back\slash' 'new
line' >escaped
cat >want <<'EOF'
\ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  back\\slash
\ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad  new\nline
EOF
cmp -s want escaped || fail "escaped names: $(cat escaped)"
"$fast" -c escaped >out || fail "-c of escaped names"
printf '%s\n' 'back\slash: OK' '\new\nline: OK' >want
cmp -s want out || fail "-c of escaped names: $(cat out)"
echo "names with \\ and a newline: escaped as coreutils does"

if [ $fails = 0 ]; then echo "all passed"; else echo "$fails failed"; exit 1; fi
