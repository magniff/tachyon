# A minimal x86-64 Linux for checking the bootstrap chain from a fresh
# clone: nothing but what docs/releases.md lists for x86_64-linux (git, a
# C compiler with the libc headers, Rust through rustup) on Debian's slim
# image, which has the POSIX utilities the scripts use. See
# bootstrap/linux-check.sh, which builds and runs it.
FROM debian:bookworm-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates curl git gcc libc6-dev \
 && rm -rf /var/lib/apt/lists/*

ENV RUSTUP_HOME=/usr/local/rustup CARGO_HOME=/usr/local/cargo PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
    | sh -s -- -y --no-modify-path --profile minimal --default-toolchain none

# The seed's pinned toolchain and its crates, prefetched so reruns are fast.
# This layer only changes with the seed's rust-toolchain.toml and lock file.
COPY rust-toolchain.toml Cargo.toml Cargo.lock /prefetch/
RUN cd /prefetch \
 && mkdir src && echo 'fn main() {}' >src/main.rs \
 && rustup toolchain install \
 && cargo fetch --locked \
 && cd / && rm -rf /prefetch
