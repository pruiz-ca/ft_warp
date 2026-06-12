#!/bin/sh

set -e

IMAGE="${1:-ft_warp}"
VERSION="${2:-local}"

echo "Building $IMAGE:core"
docker build \
  --build-arg FT_WARP_VARIANT=core \
  --build-arg FT_WARP_VERSION="$VERSION" \
  -t "$IMAGE:core" .

echo "Building $IMAGE:full"
docker build \
  --build-arg INSTALL_GRAPHICS=1 \
  --build-arg INSTALL_RUST=1 \
  --build-arg INSTALL_LLVM_EXTRA=1 \
  --build-arg FT_WARP_VARIANT=full \
  --build-arg FT_WARP_VERSION="$VERSION" \
  -t "$IMAGE:full" .
