#!/bin/sh
# Tests the generated ft_warp wrapper logic with a stubbed docker, so it runs
# in milliseconds and needs no built image. Used by CI and the pre-push hook.

set -e

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/work"

cat > "$TMP/bin/docker" <<'DOCKER'
#!/bin/sh
case "$1" in
  info)   [ -n "${STUB_ROOTLESS:-}" ] && echo "[name=seccomp name=rootless]"; exit 0 ;;
  image)  case "$3" in
            *:core) [ "${STUB_CORE:-0}" = 1 ] && exit 0 || exit 1 ;;
            *:full) [ "${STUB_FULL:-0}" = 1 ] && exit 0 || exit 1 ;;
          esac
          exit 1 ;;
  buildx) exit 0 ;;
  ps)     [ -n "${STUB_RUNNING:-}" ] && echo "$STUB_RUNNING"; exit 0 ;;
  pull)   echo "PULL $*" ;;
  run)    shift; echo "RUN $*" ;;
  exec)   shift; echo "EXEC $*" ;;
  rm)     exit 0 ;;
  *)      exit 0 ;;
esac
DOCKER
chmod +x "$TMP/bin/docker"

export HOME="$TMP/home"
mkdir -p "$HOME"
GEN_PATH="$TMP/bin:/usr/bin:/bin"

FT_WARP_SKIP_HOST_SETUP=1 PATH="$GEN_PATH" sh "$ROOT/install.sh" >/dev/null 2>&1
W="$HOME/.local/bin/ft_warp"

pass=0
fail=0
ok()  { printf '  ok    %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  FAIL  %s\n' "$1"; fail=$((fail + 1)); }

want() {
  case "$3" in
    *"$2"*) ok "$1" ;;
    *) bad "$1 (got: $3)" ;;
  esac
}

absent() {
  case "$3" in
    *"$2"*) bad "$1 (unexpected: $2)" ;;
    *) ok "$1" ;;
  esac
}

run()     { ( cd "$TMP/work" && PATH="$GEN_PATH" sh "$W" "$@" 2>/dev/null ); }
run_msg() { ( cd "$TMP/work" && PATH="$GEN_PATH" sh "$W" "$@" 2>&1 ); }

echo "Testing the ft_warp wrapper"

want "version"          "ft_warp 1.0.0" "$(run --version)"
want "version short"    "ft_warp 1.0.0" "$(run -v)"
want "help usage"       "Usage:"        "$(run --help)"
want "help ports"       "-p, --publish" "$(run -h)"

printf 'VARIANT=full\nPORTS=8080,4443:443\n' > "$TMP/work/.ftwrc"
out="$(STUB_FULL=1 run make)"
want "ftwrc selects full"   "ft_warp:full make"       "$out"
want "ftwrc port localhost" "-p 127.0.0.1:8080:8080"  "$out"
want "ftwrc port mapping"   "-p 4443:443"             "$out"
want "always amd64"         "--platform linux/amd64"  "$out"
want "mounts cache volume"  "-v ft_warp_cache:/cache" "$out"
want "names container"      "--name ft_warp-work"     "$out"
want "rootful passes uid"   "HOST_UID"                "$out"

# rootless: container-root maps to the host user, so no HOST_UID is passed
rootless="$(STUB_FULL=1 STUB_ROOTLESS=1 run make)"
absent "rootless omits HOST_UID" "HOST_UID" "$rootless"

out="$(STUB_CORE=1 run --core -p 9000 ls)"
want   "cli overrides variant" "ft_warp:core ls"        "$out"
want   "cli overrides ports"   "-p 127.0.0.1:9000:9000" "$out"
absent "cli drops ftwrc ports" "8080"                   "$out"

want "--publish is -p alias" "-p 127.0.0.1:7000:7000" "$(STUB_CORE=1 run --core --publish 7000 ls)"
rm -f "$TMP/work/.ftwrc"

printf 'PORTS=8080 -v /:/host\nVARIANT=evil\n' > "$TMP/work/.ftwrc"
out="$(STUB_CORE=1 run make)"
absent "ftwrc cannot inject docker flags" "/:/host"     "$out"
want   "bad variant falls back to detect" "ft_warp:core" "$out"
rm -f "$TMP/work/.ftwrc"

# first run, no image and no config: prompt for which variant to download
want "prompt picks full"    "ft_warp:full" "$(printf 'f\n' | run_msg make)"
want "prompt defaults core" "ft_warp:core" "$(printf '\n'  | run_msg make)"

want "update subcommand" "No ft_warp image installed" "$(run_msg update)"
want "update alias"      "No ft_warp image installed" "$(run_msg --update)"
want "doctor runs"       "ft_warp doctor"             "$(run_msg doctor)"
want "clean confirmed"   "Removed ft_warp"            "$(printf 'y\n' | run_msg clean)"
want "clean cancelled"   "Cancelled"                  "$(printf 'n\n' | run_msg clean)"

# reuse: when the project container is already running, exec into it
reuse="$(STUB_CORE=1 STUB_RUNNING=ft_warp-work run make)"
want   "reuse execs into container" "EXEC"                 "$reuse"
want   "reuse runs entrypoint"      "entrypoint.sh make"   "$reuse"
absent "reuse does not start new"   "RUN"                  "$reuse"

want "stop removes container" "Stopped ft_warp-work" "$(STUB_RUNNING=ft_warp-work run_msg stop)"

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
