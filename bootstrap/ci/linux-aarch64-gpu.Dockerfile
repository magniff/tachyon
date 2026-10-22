# The gpu image (docs/design/gpu.md §1.3): the minimal aarch64 Linux image
# plus what the shader compiler's tests and, later, the Vulkan hal need:
# spirv-val (spirv-tools), lavapipe (mesa-vulkan-drivers), the Vulkan
# loader, headers and validation layers. Built from the minimal image:
#   docker build -t vole-check:linux-aarch64-gpu \
#       -f bootstrap/ci/linux-aarch64-gpu.Dockerfile bootstrap/ci
ARG BASE=vole-check:linux-aarch64
FROM $BASE

RUN apt-get update \
 && apt-get install -y --no-install-recommends spirv-tools mesa-vulkan-drivers \
        libvulkan1 libvulkan-dev vulkan-validationlayers vulkan-tools \
 && rm -rf /var/lib/apt/lists/*
