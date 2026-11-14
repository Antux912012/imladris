# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Reproducible container build for Imladris v0.25.0 (Podman & Docker)
# Build:   podman build -t imladris-builder .   (or docker build -t imladris-builder .)
# Extract: podman run --rm -v ./dist:/dist imladris-builder cp /out/imladris /dist/

FROM fedora:41 AS builder

RUN dnf -y update && \
    dnf -y install \
      gcc \
      meson \
      ninja-build \
      vala \
      pkgconfig \
      desktop-file-utils \
      libappstream-glib \
      gtk4-devel \
      libadwaita-devel \
      gtksourceview5-devel \
      webkitgtk6.0-devel \
      libsecret-devel \
      libsoup3-devel \
      json-glib-devel \
      libgee-devel \
      glib2-devel \
      git && \
    dnf clean all

WORKDIR /src
COPY . .

RUN meson setup build-release --buildtype=release --prefix=/usr && \
    meson compile -C build-release && \
    GSETTINGS_BACKEND=memory meson test -C build-release --print-errorlogs && \
    DESTDIR=/out meson install -C build-release

FROM scratch AS artifacts
COPY --from=builder /out /
