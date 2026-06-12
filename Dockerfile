ARG UBUNTU_VERSION=22.04
ARG GDB_VERSION=16.3
ARG GDB_SHA256=bcfcd095528a987917acf9fff3f1672181694926cc18d609c99d0042c00224c5
ARG PYTHON_VERSION=3.13.1
ARG NORMINETTE_VERSION=3.3.53
ARG MLX42_VERSION=v2.4.2

FROM ubuntu:${UBUNTU_VERSION} AS gdb-builder

ARG GDB_VERSION
ARG GDB_SHA256

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        curl \
        xz-utils \
        texinfo \
        libgmp-dev \
        libmpfr-dev \
        libreadline-dev \
        python3-dev \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL -o /tmp/gdb.tar.xz https://ftp.gnu.org/gnu/gdb/gdb-${GDB_VERSION}.tar.xz \
    && echo "${GDB_SHA256}  /tmp/gdb.tar.xz" | sha256sum -c - \
    && tar -xJf /tmp/gdb.tar.xz -C /tmp \
    && rm /tmp/gdb.tar.xz \
    && cd /tmp/gdb-${GDB_VERSION} \
    && ./configure \
        --prefix=/usr/local \
        --with-python=python3 \
        --enable-tui \
        --with-system-readline \
        --disable-sim \
        --disable-gas \
        --disable-binutils \
        --disable-ld \
        --disable-gold \
        --disable-gprof \
    && make -j"$(nproc)" all-gdb \
    && make -C gdb install DESTDIR=/gdb-install \
    && strip /gdb-install/usr/local/bin/gdb \
    && rm -rf /tmp/gdb-${GDB_VERSION}

# ------------------------------------------

FROM ubuntu:${UBUNTU_VERSION}

ARG PYTHON_VERSION
ARG NORMINETTE_VERSION
ARG MLX42_VERSION

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=Europe/Berlin \
    LANG=en_US.UTF-8 \
    LC_ALL=en_US.UTF-8 \
    PYENV_ROOT=/opt/pyenv \
    CARGO_HOME=/opt/rust \
    RUSTUP_HOME=/opt/rust \
    PATH=/opt/pyenv/shims:/opt/pyenv/bin:/opt/rust/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    make \
    cmake \
    nasm \
    git \
    curl \
    wget \
    ca-certificates \
    pkg-config \
    gcc-10 \
    gcc-11 \
    g++-10 \
    g++-11 \
    g++-12 \
    clang-12 \
    clang-tools-12 \
    clang-tidy-12 \
    clangd \
    clang-format \
    valgrind \
    strace \
    ltrace \
    libssl-dev \
    zlib1g-dev \
    libbz2-dev \
    libreadline-dev \
    libsqlite3-dev \
    libncursesw5-dev \
    xz-utils \
    tk-dev \
    libxml2-dev \
    libxmlsec1-dev \
    libffi-dev \
    liblzma-dev \
    zsh \
    vim \
    less \
    file \
    gosu \
    man-db \
    manpages-dev \
    manpages-posix \
    manpages-posix-dev \
    locales \
    && locale-gen en_US.UTF-8 \
    && rm -rf /var/lib/apt/lists/*

COPY --from=gdb-builder /gdb-install/usr/local/bin/gdb     /usr/local/bin/gdb
COPY --from=gdb-builder /gdb-install/usr/local/share/gdb   /usr/local/share/gdb

RUN update-alternatives \
      --install /usr/bin/gcc gcc /usr/bin/gcc-10 100 \
      --slave   /usr/bin/gcov gcov /usr/bin/gcov-10 \
    && update-alternatives \
      --install /usr/bin/gcc gcc /usr/bin/gcc-11 50 \
    && update-alternatives \
      --install /usr/bin/g++ g++ /usr/bin/g++-10 100 \
    && update-alternatives \
      --install /usr/bin/g++ g++ /usr/bin/g++-11 50 \
    && update-alternatives \
      --install /usr/bin/g++ g++ /usr/bin/g++-12 90 \
    && update-alternatives --install /usr/bin/cc  cc  /usr/bin/clang-12 100 \
    && update-alternatives --install /usr/bin/c++ c++ /usr/bin/g++ 100 \
    && update-alternatives \
      --install /usr/bin/clang   clang   /usr/bin/clang-12   100 \
    && update-alternatives \
      --install /usr/bin/clang++ clang++ /usr/bin/clang++-12 100


ARG INSTALL_LLVM_EXTRA=0
RUN if [ "$INSTALL_LLVM_EXTRA" = "1" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            lldb-12 \
            llvm-12 \
        && rm -rf /var/lib/apt/lists/*; \
    fi


ARG INSTALL_GRAPHICS=0
RUN if [ "$INSTALL_GRAPHICS" = "1" ]; then \
        apt-get update && apt-get install -y --no-install-recommends \
            libx11-dev \
            libxrandr-dev \
            libxinerama-dev \
            libxcursor-dev \
            libxi-dev \
            libxext-dev \
            libgl1-mesa-dev \
            libglfw3 \
            libglfw3-dev \
            libwayland-dev \
            libxkbcommon-dev \
            libpulse-dev \
            libbsd-dev \
            libxcb-xfixes0-dev \
            libxcb-shape0-dev \
            libxt-dev \
            x11proto-core-dev \
        && rm -rf /var/lib/apt/lists/* \
        && git clone --depth=1 --branch ${MLX42_VERSION} https://github.com/codam-coding-college/MLX42.git /tmp/mlx42 \
        && cmake -S /tmp/mlx42 -B /tmp/mlx42/build \
            -DCMAKE_BUILD_TYPE=Release \
            -DGLFW_FETCH=OFF \
            -DBUILD_TESTS=OFF \
        && cmake --build /tmp/mlx42/build -j"$(nproc)" \
        && cmake --install /tmp/mlx42/build --prefix /usr/local \
        && rm -rf /tmp/mlx42; \
    fi


RUN git clone --depth=1 https://github.com/pyenv/pyenv.git /opt/pyenv \
    && git clone --depth=1 https://github.com/pyenv/pyenv-virtualenv.git \
                           /opt/pyenv/plugins/pyenv-virtualenv \
    && /opt/pyenv/bin/pyenv install ${PYTHON_VERSION} \
    && /opt/pyenv/bin/pyenv global ${PYTHON_VERSION} \
    && /opt/pyenv/shims/pip install --upgrade pip \
    && /opt/pyenv/shims/pip install \
        "norminette==${NORMINETTE_VERSION}" \
        mypy \
        uv \
        pipx \
    && /opt/pyenv/bin/pyenv rehash \
    && ln -sf /opt/pyenv/shims/norminette /usr/local/bin/norminette \
    && ln -sf /opt/pyenv/shims/mypy       /usr/local/bin/mypy \
    && ln -sf /opt/pyenv/shims/python     /usr/local/bin/python \
    && ln -sf /opt/pyenv/shims/python3    /usr/local/bin/python3 \
    && ln -sf /opt/pyenv/shims/pip        /usr/local/bin/pip \
    && chmod -R o+rX /opt/pyenv \
    && find /opt/pyenv -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true \
    && rm -rf /opt/pyenv/versions/${PYTHON_VERSION}/share/doc \
              /opt/pyenv/versions/${PYTHON_VERSION}/lib/python3.*/test \
              /opt/pyenv/versions/${PYTHON_VERSION}/lib/python3.*/*/test


ARG INSTALL_RUST=0
RUN if [ "$INSTALL_RUST" = "1" ]; then \
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
          | sh -s -- -y --no-modify-path --default-toolchain stable \
        && ln -sf /opt/rust/bin/rustup  /usr/local/bin/rustup \
        && ln -sf /opt/rust/bin/cargo   /usr/local/bin/cargo \
        && ln -sf /opt/rust/bin/rustc   /usr/local/bin/rustc \
        && chmod -R o+rX /opt/rust \
        && rm -rf /opt/rust/toolchains/*/share/doc \
                  /opt/rust/toolchains/*/lib/rustlib/src; \
    fi


RUN sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
      "" --unattended \
    && sed -i 's/^ZSH_THEME=.*/ZSH_THEME="risto"/' /root/.zshrc \
    && sed -i '1s|^|export PYENV_ROOT=/opt/pyenv\nexport RUSTUP_HOME=/opt/rust\nexport PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:/opt/rust/bin:$PATH"\n|' /root/.zshrc \
    && printf '%s\n' 'command -v fastfetch >/dev/null && fastfetch --config /etc/ft_warp/fastfetch.jsonc' >> /root/.zshrc \
    && cp /root/.zshrc /etc/skel/.zshrc \
    && cp -r /root/.oh-my-zsh /etc/skel/.oh-my-zsh \
    && sed -i 's|/root/.oh-my-zsh|$HOME/.oh-my-zsh|g' /etc/skel/.zshrc \
    && chsh -s /bin/zsh root

RUN printf '%s\n' \
      'export PYENV_ROOT=/opt/pyenv' \
      'export PATH="$PYENV_ROOT/bin:$PYENV_ROOT/shims:$PATH"' \
      'if command -v pyenv >/dev/null; then eval "$(pyenv init - --no-rehash)"; fi' \
      > /etc/profile.d/pyenv.sh \
    && printf '%s\n' \
      'export RUSTUP_HOME=/opt/rust' \
      'export PATH="/opt/rust/bin:$PATH"' \
      > /etc/profile.d/rust.sh \
    && chmod 644 /etc/profile.d/pyenv.sh /etc/profile.d/rust.sh

RUN printf '%s\n' \
      '#!/bin/sh' \
      'set -e' \
      'uid="${HOST_UID:-0}"' \
      'gid="${HOST_GID:-0}"' \
      'name="${HOST_USER:-user}"' \
      'if [ "$uid" -ne 0 ]; then' \
      '  getent group "$gid" >/dev/null 2>&1 || groupadd -g "$gid" "$name" 2>/dev/null || groupadd -g "$gid" "grp$gid"' \
      '  getent passwd "$uid" >/dev/null 2>&1 || useradd -u "$uid" -g "$gid" -m -s /bin/zsh "$name" 2>/dev/null || useradd -u "$uid" -g "$gid" -m -s /bin/zsh user' \
      'fi' \
      'export HOME="$(getent passwd "$uid" | cut -d: -f6)"' \
      'if [ -d /cache ]; then' \
      '  mkdir -p /cache/cargo /cache/pip /cache/ccache' \
      '  chown "$uid:$gid" /cache /cache/cargo /cache/pip /cache/ccache' \
      '  export CARGO_HOME=/cache/cargo PIP_CACHE_DIR=/cache/pip CCACHE_DIR=/cache/ccache' \
      '  export PATH="/usr/lib/ccache:$PATH"' \
      'else' \
      '  export CARGO_HOME="$HOME/.cargo"' \
      'fi' \
      'if [ "$uid" -eq 0 ]; then exec "$@"; else exec gosu "$uid:$gid" "$@"; fi' \
      > /usr/local/bin/entrypoint.sh \
    && chmod +x /usr/local/bin/entrypoint.sh

RUN arch="$(dpkg --print-architecture)" \
    && case "$arch" in amd64) ff=amd64 ;; arm64) ff=aarch64 ;; *) ff="$arch" ;; esac \
    && curl -fsSL -o /tmp/fastfetch.deb \
        "https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${ff}-polyfilled.deb" \
    && apt-get update && apt-get install -y --no-install-recommends \
        ccache \
        bear \
        /tmp/fastfetch.deb \
    && rm -f /tmp/fastfetch.deb \
    && rm -rf /var/lib/apt/lists/*

ARG FT_WARP_VARIANT=core
ARG FT_WARP_VERSION=dev
ENV FT_WARP_VARIANT=${FT_WARP_VARIANT} \
    FT_WARP_VERSION=${FT_WARP_VERSION}

RUN printf 'variant=%s\nversion=%s\n' "${FT_WARP_VARIANT}" "${FT_WARP_VERSION}" > /etc/ft_warp-release

RUN mkdir -p /etc/ft_warp \
    && printf '%s\n' \
      '        :::      ::::::::' \
      '      :+:      :+:    :+:' \
      '    +:+ +:+         +:+  ' \
      '  +#+  +:+       +#+     ' \
      '+#+#+#+#+#+   +#+        ' \
      '     #+#    #+#          ' \
      '    ###   ########       ' \
      > /etc/ft_warp/logo.txt \
    && { \
      echo '{'; \
      echo '  "logo": { "type": "file", "source": "/etc/ft_warp/logo.txt", "padding": { "top": 1, "right": 3 } },'; \
      echo '  "display": { "separator": ": " },'; \
      echo '  "modules": ['; \
      echo '    "title",'; \
      echo '    "separator",'; \
      echo "    { \"type\": \"custom\", \"key\": \"Image\",   \"format\": \"ft_warp:${FT_WARP_VARIANT}\" },"; \
      echo "    { \"type\": \"custom\", \"key\": \"Version\", \"format\": \"${FT_WARP_VERSION}\" },"; \
      echo '    { "type": "os", "key": "OS", "format": "{name} {version-id}" }'; \
      echo '  ]'; \
      echo '}'; \
    } > /etc/ft_warp/fastfetch.jsonc

LABEL org.opencontainers.image.title="ft_warp" \
      org.opencontainers.image.description="42 campus build environment (${FT_WARP_VARIANT})" \
      org.opencontainers.image.version="${FT_WARP_VERSION}" \
      org.opencontainers.image.source="https://github.com/pruiz-ca/ft_warp"

WORKDIR /root

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

CMD ["/bin/zsh"]
