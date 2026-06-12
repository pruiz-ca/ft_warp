#!/bin/sh
# Usage: tests.sh <image> <core|full>
# Asserts the ft_warp image invariants and that the toolchain actually works.
# Used by CI and runnable locally.

set -e

IMAGE="${1:?usage: tests.sh <image> <core|full>}"
VARIANT="${2:-core}"
VOL="ft_warp_testcache_${VARIANT}"

check() {
  printf '  %-26s' "$1"
  if docker run --rm "$IMAGE" sh -lc "$2" >/dev/null 2>&1; then
    echo "ok"
  else
    echo "FAIL"
    docker volume rm "$VOL" >/dev/null 2>&1 || true
    exit 1
  fi
}

# Asserts an exact value from a custom `docker run`, for cases check() can't express.
expect() {
  printf '  %-26s' "$1"
  if [ "$2" = "$3" ]; then
    echo "ok"
  else
    echo "FAIL (got: $3)"
    docker volume rm "$VOL" >/dev/null 2>&1 || true
    exit 1
  fi
}

echo "Testing $IMAGE ($VARIANT)"

# Compiler defaults the campus relies on (set via update-alternatives)
check "cc is clang"        'cc --version | grep -qi clang'
check "gcc defaults to 10" 'gcc -dumpversion | grep -q "^10"'
check "g++ defaults to 10" 'g++ -dumpversion | grep -q "^10"'

# The toolchain actually builds and runs: make + cc + linker + libc
check "make builds and runs" 'cd /tmp && printf "int main(void){return 0;}\n" > m.c && printf "all:\n\tcc m.c -o m\n" > Makefile && make >/dev/null && ./m'

# gdb is built from source with Python scripting; valgrind actually runs
check "gdb python scripting"  'gdb --batch -ex "python print(42)" 2>/dev/null | grep -q 42'
check "valgrind runs clean"   'cd /tmp && printf "int main(void){return 0;}\n" > v.c && cc v.c -o v && valgrind -q --error-exitcode=1 ./v'

# Python toolchain from pyenv (norminette regressed here once)
check "python is 3.13"     'python --version | grep -q "3.13"'
check "norminette"         'norminette --version'
check "mypy"               'mypy --version'

# Other tools students use (presence)
check "extra tools present" \
  'nasm --version && clang-format --version && ccache --version && bear --version && cmake --version'

# Image invariants
check "utf-8 locale"       'locale charmap | grep -qi utf-8'
check "variant baked in"   "[ \"\$FT_WARP_VARIANT\" = $VARIANT ] && grep -q 'variant=$VARIANT' /etc/ft_warp-release"
check "fastfetch variant"  "fastfetch --config /etc/ft_warp/fastfetch.jsonc --logo none | grep -q 'ft_warp:$VARIANT'"

# Rootful: runs as the host user, files created are owned by that uid
mapped="$(docker run --rm -e HOST_UID=4242 -e HOST_GID=4242 -e HOST_USER=tester -w /tmp "$IMAGE" \
  sh -lc 'id -u; id -un; touch f; stat -c %u f' 2>/dev/null | tr '\n' ' ')"
expect "runs as host user" "4242 tester 4242 " "$mapped"

# Persistent cache is wired up and owned correctly, for non-root and root (rootless)
nonroot="$(docker run --rm -e HOST_UID=4242 -e HOST_GID=4242 -v "$VOL":/cache -w /tmp "$IMAGE" \
  sh -lc 'echo $CARGO_HOME; stat -c %u /cache/cargo' 2>/dev/null | tr '\n' ' ')"
expect "cache as non-root" "/cache/cargo 4242 " "$nonroot"

asroot="$(docker run --rm -v "$VOL":/cache -w /tmp "$IMAGE" sh -lc 'echo $CARGO_HOME' 2>/dev/null)"
expect "cache as root (rootless)" "/cache/cargo" "$asroot"
docker volume rm "$VOL" >/dev/null 2>&1 || true

if [ "$VARIANT" = "full" ]; then
  check "cargo and rustc build" 'cd /tmp && cargo new q >/dev/null 2>&1 && cd q && cargo build >/dev/null 2>&1'
  check "lldb"                  'lldb-12 --version'
  check "MLX42 header"          'test -f /usr/local/include/MLX42/MLX42.h'
  check "graphics libs"         'pkg-config --exists libpulse wayland-client glfw3'
fi

echo "All checks passed."
