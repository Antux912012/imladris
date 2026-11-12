<!--
SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
SPDX-License-Identifier: GPL-3.0-or-later
-->

# Installation and Building Guide

Imladris (`v0.18.0`) can be installed either as an isolated **Flatpak bundle**, pre-built **native system packages** (`.deb`, `.rpm`), or compiled directly from source using **Meson and Ninja**.

---

## 1. Installation via Flatpark & Flatpak (Recommended)

Imladris is officially distributed on [Flatpark](https://flatpark.org/apps/io.github.Antux912012.Imladris/) ([flatpark/flatpark](https://github.com/flatpark/flatpark)) and publishes self-contained Flatpak bundles targeting `org.gnome.Platform//51`. The Flatpak package bundles Papirus symbolic icons, integrates `org.freedesktop.secrets` for the Arekyer Galaxy keyring, and pre-provisions the standalone **Vulkan-accelerated `llama-server`** for local AI assistance.

### Method A: Install via the Flatpark Repository
```bash
# 1. Add the Flatpark repository
flatpak remote-add --if-not-exists flatpark https://flatpark.org/repo/flatpark.flatpakrepo

# 2. Install Imladris directly
flatpak install flatpark io.github.Antux912012.Imladris

# 3. Launch Imladris
flatpak run io.github.Antux912012.Imladris
```

### Method B: Installing the Downloaded `.flatpak` Bundle
```bash
# 1. Ensure Flatpak is installed on your Linux distribution
# Ubuntu/Debian: sudo apt install flatpak
# Fedora:        sudo dnf install flatpak
# Arch Linux:    sudo pacman -S flatpak

# 2. Add Flathub repository (if not already present)
flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo

# 3. Install the GNOME 51 Platform runtime
flatpak install flathub org.gnome.Platform//51 org.gnome.Sdk//51

# 4. Install the downloaded Imladris bundle
flatpak install --user io.github.Antux912012.Imladris.flatpak

# 5. Launch Imladris
flatpak run io.github.Antux912012.Imladris
```

### Building the Flatpak Locally
The repository includes a rootless build script `build-packages.sh`:
```bash
./build-packages.sh
```
This script runs the Flatpak build finish lifecycle, compiles AppStream metadata into `repo/`, and outputs `io.github.Antux912012.Imladris.flatpak` and `imladris_0.18.0_amd64.deb`.

---

## 2. Pre-Built Native Packages (.deb & .rpm)

On every release ([v0.18.0 Releases](https://github.com/Antux912012/imladris/releases/tag/v0.18.0)), pre-built binary packages are available:

### Debian / Ubuntu (`.deb`)
```bash
sudo dpkg -i imladris_0.18.0_amd64.deb
sudo apt-get install -f  # Resolves any missing runtime dependencies
```

### Fedora / RHEL (`.rpm`)
```bash
sudo dnf install ./imladris-0.18.0-1.fc44.x86_64.rpm
```

---

## 3. Compiling from Source (Meson & Ninja)

### Required Build Dependencies

#### Debian / Ubuntu / Linux Mint
```bash
sudo apt update
sudo apt install -y \
    valac \
    meson \
    ninja-build \
    gcc \
    pkg-config \
    libgtk-4-dev \
    libadwaita-1-dev \
    libgtksourceview-5-dev \
    libwebkitgtk-6.0-dev \
    libjavascriptcoregtk-6.0-dev \
    libsoup-3.0-dev \
    libjson-glib-dev \
    libsecret-1-dev \
    libgee-0.8-dev \
    papirus-icon-theme \
    pandoc \
    r-base \
    python3-venv \
    libreoffice-impress
```

#### Fedora / RHEL
```bash
sudo dnf install -y \
    valac \
    meson \
    ninja-build \
    gcc \
    pkgconf-pkg-config \
    gtk4-devel \
    libadwaita-devel \
    gtksourceview5-devel \
    webkitgtk6.0-devel \
    javascriptcoregtk6.0-devel \
    libsoup3-devel \
    json-glib-devel \
    libsecret-devel \
    gee08-devel \
    papirus-icon-theme \
    pandoc \
    R-core \
    python3-virtualenv \
    libreoffice-impress
```

#### Arch Linux / Manjaro / CachyOS
```bash
sudo pacman -S --needed \
    vala \
    meson \
    ninja \
    gcc \
    pkgconf \
    gtk4 \
    libadwaita \
    gtksourceview5 \
    webkitgtk-6.0 \
    libsoup3 \
    json-glib \
    libsecret \
    libgee \
    papirus-icon-theme \
    pandoc \
    r \
    python \
    libreoffice-fresh
```

### Build and Installation Commands

```bash
git clone https://github.com/Antux912012/imladris.git
cd imladris

# Configure build directory
meson setup build --prefix=/usr

# Compile executable and resources
meson compile -C build

# Run all 7 unit test suites
meson test -C build --print-errorlogs

# Install to system
sudo meson install -C build
```

---

## 4. Hardware & WebKit Rendering Settings

Imladris features a hardware acceleration toggle under **Preferences $\rightarrow$ General $\rightarrow$ Hardware & Rendering**:
- **Hardware Acceleration (Enabled by default)**: Uses host OpenGL / Vulkan GPU drivers for rendering WebKit previews, interactive plots, and mathematical/chemical formulas.
- **Software Rendering (Fallback)**: If running inside a virtual machine (QEMU, VirtualBox, VMware) or headless environment, toggle this setting off to enforce software-rendered rasterization.
