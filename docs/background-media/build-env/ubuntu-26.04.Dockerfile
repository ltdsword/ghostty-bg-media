FROM ubuntu:26.04

ENV DEBIAN_FRONTEND=noninteractive

RUN apt-get update && \
    layer_shell_pkg="" && \
    if apt-cache show libgtk4-layer-shell-dev >/dev/null 2>&1; then \
      layer_shell_pkg="libgtk4-layer-shell-dev"; \
    fi && \
    apt-get install -y --no-install-recommends \
      build-essential \
      blueprint-compiler \
      ca-certificates \
      gettext \
      git \
      libadwaita-1-dev \
      libbz2-dev \
      libgtk-4-dev \
      libonig-dev \
      libxml2-utils \
      meson \
      ninja-build \
      pkg-config \
      xz-utils \
      $layer_shell_pkg && \
    rm -rf /var/lib/apt/lists/*

RUN set -eu; \
    blueprint_version="$(dpkg-query -W -f='${Version}' blueprint-compiler)"; \
    printf 'blueprint-compiler-apt=%s\n' "$blueprint_version"; \
    if ! dpkg --compare-versions "$blueprint_version" ge 0.20.0; then \
      git clone --depth 1 --branch v0.20.0 \
        https://gitlab.gnome.org/GNOME/blueprint-compiler.git \
        /tmp/blueprint-compiler; \
      meson setup /tmp/blueprint-compiler/build /tmp/blueprint-compiler \
        --prefix=/usr/local; \
      meson install -C /tmp/blueprint-compiler/build; \
      rm -rf /tmp/blueprint-compiler; \
    fi; \
    printf 'gtk4='; pkg-config --modversion gtk4; \
    printf 'libadwaita='; pkg-config --modversion libadwaita-1; \
    printf 'blueprint-compiler='; blueprint-compiler --version

WORKDIR /src
