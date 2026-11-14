#!/usr/bin/env bash
# SPDX-FileCopyrightText: 2026 Antonio De Gaetano <antux912012@users.noreply.github.com>
# SPDX-License-Identifier: GPL-3.0-or-later
#
# Imladris Universal Quick Installer
# Usage:
#   curl -fsSL https://antux912012.github.io/imladris/install.sh | bash
#   wget -qO- https://antux912012.github.io/imladris/install.sh | bash
#
# Options:
#   --flatpark    Force installation via Flatpark (Recommended)
#   --flathub     Force installation via Flathub
#   --native      Force download and installation of native package (.deb / .rpm)
#   --dry-run     Print actions without executing
#   --help, -h    Show this help message

set -euo pipefail

VERSION="0.25.0"
REPO="Antux912012/imladris"
FLATPARK_REPO="https://flatpark.org/repo/flatpark.flatpakrepo"
APP_ID="io.github.Antux912012.Imladris"

# Nordic Color Palette for Terminal
BOLD="\033[1m"
RESET="\033[0m"
FROST_CYAN="\033[38;2;136;192;208m"
FROST_BLUE="\033[38;2;129;161;193m"
AURORA_GOLD="\033[38;2;235;203;139m"
AURORA_GREEN="\033[38;2;163;190;140m"
AURORA_RED="\033[38;2;191;97;106m"
SNOW_WHITE="\033[38;2;236;239;244m"
POLAR_GREY="\033[38;2;76;86;106m"

print_banner() {
    echo -e "${FROST_CYAN}"
    echo -e "    ╔═════════════════════════════════════════════════════════════════════════╗"
    echo -e "    ║                                                                         ║"
    echo -e "    ║   ${AURORA_GOLD}✧  I M L A D R I S  v${VERSION}  ✧${FROST_CYAN}                                     ║"
    echo -e "    ║   ${SNOW_WHITE}The Last Homely House East of the Sea — Scientific Workbench${FROST_CYAN}          ║"
    echo -e "    ║   ${FROST_BLUE}Native GTK4 & Libadwaita • Quarto • R • Python • Elrond AI${FROST_CYAN}            ║"
    echo -e "    ║                                                                         ║"
    echo -e "    ╚═════════════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
}

log_info() {
    echo -e "${FROST_BLUE}[*]${RESET} ${SNOW_WHITE}$1${RESET}"
}

log_success() {
    echo -e "${AURORA_GREEN}[✔]${RESET} ${BOLD}${SNOW_WHITE}$1${RESET}"
}

log_warn() {
    echo -e "${AURORA_GOLD}[!]${RESET} ${AURORA_GOLD}$1${RESET}"
}

log_error() {
    echo -e "${AURORA_RED}[✘]${RESET} ${BOLD}${AURORA_RED}$1${RESET}" >&2
}

METHOD="auto"
DRY_RUN=false

for arg in "$@"; do
    case "$arg" in
        --flatpark) METHOD="flatpark" ;;
        --flathub)  METHOD="flathub" ;;
        --native)   METHOD="native" ;;
        --dry-run)  DRY_RUN=true ;;
        --help|-h)
            print_banner
            echo -e "${BOLD}Usage:${RESET} curl -fsSL https://antux912012.github.io/imladris/install.sh | bash [options]"
            echo ""
            echo "Options:"
            echo "  --flatpark    Install via Flatpark repository (Recommended)"
            echo "  --flathub     Install via Flathub"
            echo "  --native      Install native package (.deb for Debian/Ubuntu, .rpm for Fedora)"
            echo "  --dry-run     Display commands without running them"
            echo "  --help, -h    Display this help guide"
            exit 0
            ;;
        *)
            log_warn "Unknown option '$arg', continuing with auto-detection."
            ;;
    esac
done

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        DISTRO_ID="${ID:-unknown}"
        DISTRO_LIKE="${ID_LIKE:-}"
        DISTRO_NAME="${NAME:-Linux}"
    else
        DISTRO_ID="unknown"
        DISTRO_LIKE=""
        DISTRO_NAME="Linux"
    fi
}

has_cmd() {
    command -v "$1" >/dev/null 2>&1
}

run_step() {
    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${POLAR_GREY}[DRY-RUN] ${1}${RESET}"
    else
        eval "$1"
    fi
}

install_via_flatpark() {
    log_info "Configuring Flatpark repository and installing Imladris Flatpak..."
    if ! has_cmd flatpak; then
        log_warn "Flatpak is not installed. Attempting to install flatpak package..."
        if has_cmd apt-get; then
            run_step "sudo apt-get update && sudo apt-get install -y flatpak"
        elif has_cmd dnf; then
            run_step "sudo dnf install -y flatpak"
        elif has_cmd pacman; then
            run_step "sudo pacman -S --noconfirm flatpak"
        elif has_cmd zypper; then
            run_step "sudo zypper install -y flatpak"
        else
            log_error "Could not find a package manager to install Flatpak. Please install flatpak manually."
            exit 1
        fi
    fi

    log_info "Registering Flatpark remote repository..."
    run_step "flatpak remote-add --if-not-exists flatpark ${FLATPARK_REPO}"

    log_info "Installing ${APP_ID} from Flatpark..."
    run_step "flatpak install -y --noninteractive flatpark ${APP_ID}"

    log_success "Imladris v${VERSION} installed successfully via Flatpark!"
    echo ""
    echo -e "${BOLD}${FROST_CYAN}To launch:${RESET} flatpak run ${APP_ID}"
}

install_via_flathub() {
    log_info "Installing Imladris via Flathub..."
    if ! has_cmd flatpak; then
        log_error "Flatpak is required for Flathub installation."
        exit 1
    fi
    run_step "flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
    run_step "flatpak install -y --noninteractive flathub ${APP_ID}"
    log_success "Imladris v${VERSION} installed successfully via Flathub!"
}

install_native_deb() {
    log_info "Installing native Debian/Ubuntu package (.deb)..."
    TMP_DIR=$(mktemp -d)
    DEB_URL="https://github.com/${REPO}/releases/download/v${VERSION}/imladris_${VERSION}_amd64.deb"
    DEB_FILE="${TMP_DIR}/imladris_${VERSION}_amd64.deb"

    log_info "Downloading ${DEB_URL}..."
    if has_cmd curl; then
        run_step "curl -fsSL -o '${DEB_FILE}' '${DEB_URL}'"
    elif has_cmd wget; then
        run_step "wget -q -O '${DEB_FILE}' '${DEB_URL}'"
    else
        log_error "Neither curl nor wget is available."
        exit 1
    fi

    log_info "Installing package with dpkg and resolving runtime dependencies..."
    run_step "sudo dpkg -i '${DEB_FILE}' || sudo apt-get install -f -y"
    rm -rf "${TMP_DIR}"

    log_success "Imladris v${VERSION} installed successfully into /usr/bin/imladris!"
    echo ""
    echo -e "${BOLD}${FROST_CYAN}To launch:${RESET} imladris"
}

install_native_rpm() {
    log_info "Installing native RPM package on ${DISTRO_NAME}..."
    RPM_URL="https://github.com/${REPO}/releases/download/v${VERSION}/imladris-${VERSION}-1.fc41.x86_64.rpm"
    
    if has_cmd dnf; then
        run_step "sudo dnf install -y '${RPM_URL}'"
    elif has_cmd zypper; then
        run_step "sudo zypper install -y '${RPM_URL}'"
    elif has_cmd rpm; then
        run_step "sudo rpm -Uvh '${RPM_URL}'"
    else
        log_error "No supported RPM package manager found (dnf, zypper, rpm)."
        exit 1
    fi

    log_success "Imladris v${VERSION} installed successfully into /usr/bin/imladris!"
    echo ""
    echo -e "${BOLD}${FROST_CYAN}To launch:${RESET} imladris"
}

# --- Main Execution ---
print_banner
detect_distro
log_info "Target System: ${DISTRO_NAME} (${DISTRO_ID}${DISTRO_LIKE:+ / $DISTRO_LIKE}) on $(uname -m)"

if [[ "$METHOD" == "flatpark" ]]; then
    install_via_flatpark
elif [[ "$METHOD" == "flathub" ]]; then
    install_via_flathub
elif [[ "$METHOD" == "native" ]]; then
    if [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        install_native_deb
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "almalinux" || "$DISTRO_ID" == "centos" || "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_ID" == "opensuse"* ]]; then
        install_native_rpm
    else
        log_warn "No pre-built native package recognized for '${DISTRO_ID}'. Falling back to Flatpark."
        install_via_flatpark
    fi
else
    # Auto-detection mode:
    # 1. If flatpak is already installed, prefer Flatpark sandbox
    if has_cmd flatpak; then
        log_info "Flatpak subsystem detected. Selecting Flatpark sandboxed bundle (Recommended)."
        install_via_flatpark
    elif [[ "$DISTRO_ID" == "debian" || "$DISTRO_ID" == "ubuntu" || "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
        log_info "Debian/Ubuntu family detected. Installing native .deb package."
        install_native_deb
    elif [[ "$DISTRO_ID" == "fedora" || "$DISTRO_ID" == "rhel" || "$DISTRO_ID" == "almalinux" || "$DISTRO_ID" == "centos" || "$DISTRO_LIKE" == *"fedora"* || "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_ID" == "opensuse"* ]]; then
        log_info "RPM-based system detected. Installing native .rpm package."
        install_native_rpm
    elif [[ "$DISTRO_ID" == "arch" || "$DISTRO_LIKE" == *"arch"* ]]; then
        log_info "Arch Linux detected. Installing Flatpak runtime or AUR."
        install_via_flatpark
    else
        log_info "Defaulting to Flatpark distribution."
        install_via_flatpark
    fi
fi

echo ""
echo -e "${AURORA_GOLD}✧ “Here you will find rest and wisdom to heal the weary mind.” — Rivendell Lore ✧${RESET}"
echo -e "${SNOW_WHITE}Project Homepage: ${FROST_CYAN}https://antux912012.github.io/imladris/${RESET}"
echo -e "${SNOW_WHITE}GitHub Source:    ${FROST_CYAN}https://github.com/Antux912012/imladris${RESET}"
echo -e "${SNOW_WHITE}Author Portfolio: ${FROST_CYAN}https://antux912012.github.io/${RESET}"
