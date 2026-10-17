#!/bin/sh
# The timings of the README: sha256sum against the system's tools on
# three workloads, the best of 5 runs each (warm cache). Not run by the
# tests (they are this machine's).
#
# usage: sh bench.sh DIR [TOOL...]
#   DIR    where to make the inputs (1 GiB, and 10,000 files of 0-16 KiB)
#   TOOL   commands to time (default: ./sha256sum and the system's)
set -u
dir=$1
shift
here=$(pwd)
if [ $# = 0 ]; then
    set -- "$here/sha256sum"
    for t in sha256sum /sbin/sha256sum; do
        command -v $t >/dev/null 2>&1 && { set -- "$@" $t; break; }
    done
    command -v openssl >/dev/null 2>&1 && set -- "$@" "openssl dgst -sha256"
    command -v shasum >/dev/null 2>&1 && set -- "$@" "shasum -a 256"
fi
mkdir -p "$dir/small"
cd "$dir" || exit 1
[ -f big ] || head -c 1073741824 /dev/urandom >big
if [ ! -f small/f9999 ]; then
    i=0
    while [ $i -lt 10000 ]; do
        head -c $((i * 7919 % 16384 + 1)) /dev/urandom >small/f$i
        i=$((i + 1))
    done
fi
cat big >/dev/null

# Prints the best wall time of 5 runs of the shell command $1, in seconds.
best() {
    perl -MTime::HiRes=time -e '
        my $best = 1e9;
        for (1..5) {
            my $t = time; system("sh", "-c", $ARGV[0]) == 0 or die "failed: $ARGV[0]\n";
            my $d = time - $t; $best = $d if $d < $best;
        }
        printf "%.3f", $best;' "$1"
}

load=$( (uptime 2>/dev/null || cat /proc/loadavg) | sed 's/.*load average[s]*: //')
echo "load averages before: $load"
printf '%-28s %16s %16s %16s\n' tool "1 GiB file" "10,000 files" "1 GiB pipe"
for t in "$@"; do
    a=$(best "$t big >/dev/null")
    b=$(cd small && best "$t * >/dev/null")
    c=$(best "cat big | $t >/dev/null")
    gb() { perl -e 'printf "%.2f", 1.073741824 / $ARGV[0]' "$1"; }
    printf '%-28s %7s s %4s GB/s %7s s %8s %7s s %4s GB/s\n' "$(echo "$t" | sed "s#^$here/#./#")" \
        "$a" "$(gb "$a")" "$b" "" "$c" "$(gb "$c")"
done
