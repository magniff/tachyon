# Toolchain for running tachyon's golden tests on non-x86-64-Linux hosts:
#   TACHYON_DOCKER=1 cargo test --test run
FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends nasm gcc libc6-dev coreutils \
    && rm -rf /var/lib/apt/lists/*
