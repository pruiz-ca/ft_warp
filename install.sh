#!/bin/sh

set -e

VERSION="1.0.0"
IMAGE="ghcr.io/pruiz-ca/ft_warp"
HOSTNAME="ft_warp"
BIN_DIR="$HOME/.local/bin"
BIN="$BIN_DIR/ft_warp"

BOLD="$(printf '\033[1m')"
GREEN="$(printf '\033[32m')"
YELLOW="$(printf '\033[33m')"
RED="$(printf '\033[31m')"
RESET="$(printf '\033[0m')"

ok()   { printf "${GREEN}  ✓${RESET}  %s\n" "$1"; }
info() { printf "${BOLD}  →${RESET}  %s\n" "$1"; }
warn() { printf "${YELLOW}  !${RESET}  %s\n" "$1"; }
die()  { printf "${RED}  ✗${RESET}  %s\n" "$1" >&2; exit 1; }

setup_xquartz() {
  if [ ! -d /opt/X11 ]; then
    command -v brew >/dev/null 2>&1 || { warn "Install XQuartz from https://www.xquartz.org for graphics"; return; }
    info "Installing XQuartz ..."
    brew install --cask xquartz || { warn "XQuartz install failed"; return; }
  fi
  defaults write org.xquartz.X11 nolisten_tcp -bool false >/dev/null 2>&1 || true
  defaults write org.xquartz.X11 enable_iglx -bool true >/dev/null 2>&1 || true
  ok "XQuartz configured (open it yourself when you need graphics)"
}

setup_pulseaudio() {
  if ! command -v pulseaudio >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || { warn "Install PulseAudio for sound"; return; }
    info "Installing PulseAudio ..."
    brew install pulseaudio || { warn "PulseAudio install failed"; return; }
  fi
  pulseaudio --check 2>/dev/null \
    || pulseaudio --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \
                  --exit-idle-time=-1 --daemon >/dev/null 2>&1 || true
  ok "PulseAudio ready"
}

printf '\n%sft_warp%s compile like in your 42 campus, from anywhere\n\n' "$BOLD" "$RESET"

command -v docker >/dev/null 2>&1 || die "Docker is not installed. Get it at https://docs.docker.com/get-docker/"
docker info >/dev/null 2>&1 || die "Docker is not running. Start Docker Desktop and try again."
ok "Docker is running"

if [ "$(uname -s)" = "Darwin" ] && [ -z "$FT_WARP_SKIP_HOST_SETUP" ]; then
  setup_xquartz
  setup_pulseaudio
fi

mkdir -p "$BIN_DIR"

cat > "$BIN" << EOF
#!/bin/sh
IMAGE="${IMAGE}"
VERSION="${VERSION}"
PLATFORM="--platform linux/amd64"

usage() {
cat <<'USAGE'
ft_warp - the 42 campus environment in a container

Usage:
  ft_warp [options] [command]
  ftw     [options] [command]

Commands:
  update           pull the latest of the images you already have
  doctor           check the setup and report problems
  stop             stop this project's container
  clean            remove all ft_warp containers, images and cached data

Options:
  --core           use the core image (C, C++, Python)
  --full           use the full image (adds graphics, Rust, lldb/llvm)
  -p, --publish    publish ports, comma separated (e.g. 8080,4443:443)
  -h, --help       show this help
  -v, --version    show the version

A .ftwrc file in the project sets defaults (command line overrides them):
  VARIANT=full
  PORTS=8080,4443:443
USAGE
}

doctor() {
  echo "ft_warp doctor (wrapper \$VERSION)"
  if docker info >/dev/null 2>&1; then
    if docker info -f '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless; then
      echo "  ok    docker is running (rootless)"
    else
      echo "  ok    docker is running"
    fi
  else
    echo "  FAIL  docker is not running"
  fi
  case ":\$PATH:" in
    *":\$HOME/.local/bin:"*) echo "  ok    ~/.local/bin on PATH" ;;
    *) echo "  warn  ~/.local/bin is not on PATH" ;;
  esac
  for t in core full; do
    size="\$(docker image inspect "\$IMAGE:\$t" --format '{{.Size}}' 2>/dev/null)"
    if [ -n "\$size" ]; then
      echo "  ok    \$t image present (\$((size / 1000000)) MB)"
    else
      echo "  --    \$t image not pulled"
    fi
  done
  if docker image inspect "\$IMAGE:full" >/dev/null 2>&1; then
    echo "  here: ft_warp runs 'full'"
  elif docker image inspect "\$IMAGE:core" >/dev/null 2>&1; then
    echo "  here: ft_warp runs 'core'"
  else
    echo "  here: ft_warp would download an image first"
  fi
  if [ "\$(uname -s)" = "Darwin" ]; then
    [ -d /opt/X11 ] && echo "  ok    XQuartz installed" || echo "  warn  XQuartz not installed (needed for graphics)"
    pgrep -qx Xquartz >/dev/null 2>&1 && echo "  ok    XQuartz running" || echo "  --    XQuartz not running (open it for graphics)"
    command -v pulseaudio >/dev/null 2>&1 && echo "  ok    PulseAudio installed" || echo "  warn  PulseAudio not installed (needed for sound)"
  fi
}

check_update() {
  marker="\$HOME/.cache/ft_warp/checked"
  mkdir -p "\$HOME/.cache/ft_warp"
  if [ -f "\$marker" ] && [ -z "\$(find "\$marker" -mtime +1 2>/dev/null)" ]; then
    return 0
  fi
  touch "\$marker"
  have="\$(docker image inspect "\$IMAGE:\$TAG" --format '{{index .RepoDigests 0}}' 2>/dev/null | sed 's/.*@//')"
  [ -n "\$have" ] || return 0
  latest="\$(docker buildx imagetools inspect "\$IMAGE:\$TAG" --format '{{.Manifest.Digest}}' 2>/dev/null)"
  [ -n "\$latest" ] || return 0
  [ "\$have" = "\$latest" ] && return 0
  printf 'A new ft_warp:%s is available. Update now? [y/N] ' "\$TAG" >&2
  read -r answer
  case "\$answer" in
    y|Y) docker pull \$PLATFORM "\$IMAGE:\$TAG" ;;
  esac
}

clean() {
  printf 'Remove all ft_warp containers, images and the cache volume? [y/N] ' >&2
  read -r answer
  case "\$answer" in
    y|Y) ;;
    *) echo "Cancelled" >&2; return 0 ;;
  esac
  docker ps -aq --filter name=ft_warp- 2>/dev/null | while read -r c; do
    docker rm -f "\$c" >/dev/null 2>&1
  done
  docker rmi "\$IMAGE:core" "\$IMAGE:full" "\$IMAGE:latest" >/dev/null 2>&1
  docker volume rm ft_warp_cache >/dev/null 2>&1
  echo "Removed ft_warp containers, images and cache volume."
}

add_ports() {
  oldifs=\$IFS; IFS=,
  for p in \$1; do
    case "\$p" in
      ''|*[!0-9.:]*) continue ;;
      *:*) ports="\$ports -p \$p" ;;
      *)   ports="\$ports -p 127.0.0.1:\$p:\$p" ;;
    esac
  done
  IFS=\$oldifs
}

cfg_variant=""
cfg_ports=""
if [ -f .ftwrc ]; then
  while IFS= read -r line; do
    trimmed="\$(printf '%s' "\$line" | sed 's/^[[:space:]]*//')"
    case "\$trimmed" in ''|\\#*) continue ;; esac
    key="\${trimmed%%=*}"
    val="\${trimmed#*=}"
    [ "\$key" = "\$trimmed" ] && continue
    key="\$(printf '%s' "\$key" | tr -d '[:space:]')"
    val="\$(printf '%s' "\$val" | sed 's/^[[:space:]]*//; s/[[:space:]]*\$//')"
    case "\$key" in
      VARIANT) cfg_variant="\$val" ;;
      PORTS)   cfg_ports="\$val" ;;
    esac
  done < .ftwrc
fi

project="\$(basename "\$PWD")"
cname="ft_warp-\$(printf '%s' "\$project" | tr -c 'A-Za-z0-9_.-' '_')"

ports=""
TAG=""
ports_set=0
while [ \$# -gt 0 ]; do
  case "\$1" in
    -p|--publish) shift; add_ports "\${1:-}"; ports_set=1; shift ;;
    --full) TAG="full"; shift ;;
    --core) TAG="core"; shift ;;
    -h|--help) usage; exit 0 ;;
    -v|--version) echo "ft_warp \$VERSION"; exit 0 ;;
    doctor) doctor; exit 0 ;;
    clean) clean; exit 0 ;;
    stop) docker rm -f "\$cname" >/dev/null 2>&1 && echo "Stopped \$cname" || echo "No ft_warp container for this project"; exit 0 ;;
    update|--update)
      pulled=0
      for t in core full; do
        if docker image inspect "\$IMAGE:\$t" >/dev/null 2>&1; then
          echo "Updating \$IMAGE:\$t ..." >&2
          docker pull \$PLATFORM "\$IMAGE:\$t"
          pulled=1
        fi
      done
      [ "\$pulled" = 0 ] && echo "No ft_warp image installed yet. Run ft_warp to download one." >&2
      exit 0 ;;
    *) break ;;
  esac
done

# Rootless docker maps container-root to the host user, so dropping to HOST_UID
# would mis-own mounted files. Only pass the host ids when docker is rootful.
uidargs="-e HOST_UID=\$(id -u) -e HOST_GID=\$(id -g) -e HOST_USER=\$(id -un)"
docker info -f '{{.SecurityOptions}}' 2>/dev/null | grep -q rootless && uidargs=""

if docker ps --format '{{.Names}}' 2>/dev/null | grep -qx "\$cname"; then
  [ "\$#" -eq 0 ] && set -- /bin/zsh
  exec docker exec -it \$uidargs \\
    -w "/\$project" \\
    "\$cname" /usr/local/bin/entrypoint.sh "\$@"
fi

if [ -z "\$TAG" ]; then
  case "\$cfg_variant" in core|full) TAG="\$cfg_variant" ;; esac
fi
[ "\$ports_set" = 0 ] && [ -n "\$cfg_ports" ] && add_ports "\$cfg_ports"

if [ -z "\$TAG" ]; then
  if docker image inspect "\$IMAGE:full" >/dev/null 2>&1; then
    TAG="full"
  elif docker image inspect "\$IMAGE:core" >/dev/null 2>&1; then
    TAG="core"
  else
    printf 'No ft_warp image found. Download which? [C]ore / [f]ull: ' >&2
    read -r choice
    case "\$choice" in
      f|F|full) TAG="full" ;;
      *) TAG="core" ;;
    esac
  fi
fi

if docker image inspect "\$IMAGE:\$TAG" >/dev/null 2>&1; then
  check_update
else
  echo "Downloading \$IMAGE:\$TAG ..." >&2
  docker pull \$PLATFORM "\$IMAGE:\$TAG"
fi

docker rm "\$cname" >/dev/null 2>&1 || true

display=""
sdl=""

if [ "\$(uname -s)" = "Darwin" ]; then
  sdl="-e SDL_RENDER_DRIVER=software -e SDL_FRAMEBUFFER_ACCELERATION=0"
  if command -v pulseaudio >/dev/null 2>&1; then
    pulseaudio --check 2>/dev/null \\
      || pulseaudio --load="module-native-protocol-tcp auth-ip-acl=127.0.0.1 auth-anonymous=1" \\
                    --exit-idle-time=-1 --daemon >/dev/null 2>&1 || true
    sdl="\$sdl -e SDL_AUDIODRIVER=pulseaudio -e PULSE_SERVER=host.docker.internal"
  else
    sdl="\$sdl -e SDL_AUDIODRIVER=dummy"
  fi
  if [ -d /opt/X11 ] && pgrep -qx Xquartz >/dev/null 2>&1; then
    DISPLAY=:0 /opt/X11/bin/xhost + 127.0.0.1 >/dev/null 2>&1 || true
    display="-e DISPLAY=host.docker.internal:0"
  fi
else
  [ -n "\$DISPLAY" ] && display="-e DISPLAY=\$DISPLAY -v /tmp/.X11-unix:/tmp/.X11-unix"
fi

exec docker run --rm -it \$PLATFORM \$display \$sdl \$ports \$uidargs \\
  --name "\$cname" \\
  --hostname ${HOSTNAME} \\
  -v ft_warp_cache:/cache \\
  -v "\$PWD:/\$project" \\
  -w "/\$project" \\
  "\$IMAGE:\$TAG" "\$@"
EOF

chmod +x "$BIN"
ln -sf ft_warp "$BIN_DIR/ftw"
ok "Installed ft_warp → $BIN (ftw shorthand too)"

case ":$PATH:" in
  *":$BIN_DIR:"*) ;;
  *) warn "Add $BIN_DIR to your PATH" ;;
esac

printf '\n%sDone.%s\n\n' "$BOLD" "$RESET"
printf "  ft_warp           shell in your project (full image if present, else core)\n"
printf "  ft_warp --full    graphics + Rust (so_long, cub3D, miniRT...)\n"
printf "  ft_warp --core    lean image (C / C++ / Python)\n"
printf "  ftw               shorthand for ft_warp\n\n"
