# A minimal AArch64 Linux for the native half of the aarch64-linux check
# (bootstrap/aarch64-linux-check.sh): the compiler is cross-built for
# aarch64-linux where the bootstrap chain runs (the Rust seed has no
# aarch64-linux backend), then rebuilt with itself and tested here. Needs
# git, a C compiler with the libc headers, binutils (objdump, for
# tests/objcheck.sh) and gdb (the debugger check), on Debian's slim image,
# which has the POSIX utilities the scripts use.
# Debian bookworm-slim, by the digest of the manifest for the platform
# (given by the check script).
ARG BASE=debian:bookworm-slim
FROM $BASE

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates git gcc libc6-dev binutils gdb \
 && rm -rf /var/lib/apt/lists/*
