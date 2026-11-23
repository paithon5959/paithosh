#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=installer/lib/audit.sh
source "$SCRIPT_DIR/installer/lib/audit.sh"

MODE="auto"
DRY_RUN="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --cli) MODE="cli"; shift ;;
        --gui) MODE="gui"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        -h|--help)
            cat <<'EOF'
Usage: ./install.sh [--gui|--cli] [--dry-run]
  --gui      Force Quickshell Wayland GUI installer
  --cli      Force TTY CLI installer
  --dry-run  Simulate installation without modifying the system
EOF
            exit 0
            ;;
        *) echo "[paithosh] Unknown option: $1 (see --help)" >&2; exit 2 ;;
    esac
done

IFS='|' read -r DISTRO_ID FAMILY PKG_MGR PRETTY_NAME <<<"$(detect_distro)"

ensure_python3() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    echo "[paithosh] Python 3 is required by the Paithosh installer."
    echo "[paithosh] Detected: $PRETTY_NAME ($PKG_MGR)"
    local ans=""
    read -r -p "Install Python 3 now? [Y/n]: " ans || ans="n"
    if [[ "${ans,,}" == "n" ]]; then
        echo "[paithosh] Cannot continue without python3. Exiting." >&2
        exit 1
    fi
    case "$PKG_MGR" in
        pacman) sudo pacman -S --needed --noconfirm python ;;
        paru|yay) "$PKG_MGR" -S --needed --noconfirm python ;;
        dnf|dnf5) sudo "$PKG_MGR" install -y python3 ;;
        apt) sudo apt-get update && sudo DEBIAN_FRONTEND=noninteractive apt-get install -y python3 ;;
        *)
            echo "[paithosh] Unsupported package manager '$PKG_MGR'. Please install python3 manually." >&2
            exit 1
            ;;
    esac
}

can_run_gui() {
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 1
    [[ "${XDG_CURRENT_DESKTOP:-}" != *[Gg][Nn][Oo][Mm][Ee]* ]] || return 1
    return 0
}

ensure_quickshell() {
    if command -v qs >/dev/null 2>&1; then
        return 0
    fi

    echo "[paithosh] Quickshell (qs) is needed for the GUI installer."
    echo "[paithosh] Detected: $PRETTY_NAME ($PKG_MGR)"
    local ans=""
    read -r -p "Install Quickshell now? [Y/n]: " ans || ans="n"
    if [[ "${ans,,}" == "n" ]]; then
        return 1
    fi

    case "$PKG_MGR" in
        pacman)
            echo "[paithosh] Trying quickshell via pacman (install paru/yay for quickshell-git if unavailable)..."
            sudo pacman -S --needed --noconfirm quickshell || return 1
            ;;
        paru|yay) "$PKG_MGR" -S --needed --noconfirm quickshell-git || return 1 ;;
        dnf|dnf5)
            if ! grep -qs "enabled=1" /etc/yum.repos.d/*copr*[Hh]yprland*.repo 2>/dev/null; then
                echo "[paithosh] Enabling Fedora COPR lionheartp/Hyprland..."
                sudo "$PKG_MGR" copr enable -y lionheartp/Hyprland || return 1
            fi
            sudo "$PKG_MGR" install -y quickshell || return 1
            ;;
        apt)
            echo "[paithosh] Quickshell is not in official Debian/Ubuntu apt repos (see https://quickshell.org)."
            return 1
            ;;
        *)
            echo "[paithosh] Unsupported package manager '$PKG_MGR'. Please install Quickshell manually."
            return 1
            ;;
    esac
}

ensure_python3

CLI_ARGS=()
[[ "$DRY_RUN" == "true" ]] && CLI_ARGS+=("--dry-run")

RUN_GUI="false"
if [[ "$MODE" == "gui" ]]; then
    if ! can_run_gui; then
        echo "[paithosh] Error: GUI installer requires a wlroots/KDE Wayland session (wlr-layer-shell)." >&2
        exit 1
    fi
    if ! ensure_quickshell; then
        echo "[paithosh] Cannot launch GUI without Quickshell." >&2
        exit 1
    fi
    RUN_GUI="true"
elif [[ "$MODE" == "auto" ]] && can_run_gui; then
    if ensure_quickshell; then
        RUN_GUI="true"
    else
        echo "[paithosh] Falling back to CLI Installer..."
    fi
fi

if [[ "$RUN_GUI" == "true" ]]; then
    echo "[paithosh] Wayland session detected — launching Paithosh GUI Installer..."
    GUI_ENV=()
    [[ "$DRY_RUN" == "true" || "${PAITHOSH_INSTALLER_DRY_RUN:-0}" == "1" ]] && GUI_ENV+=("PAITHOSH_INSTALLER_DRY_RUN=1")
    rc=0
    if [[ ${#GUI_ENV[@]} -gt 0 ]]; then
        env "${GUI_ENV[@]}" qs -p "$SCRIPT_DIR/shell/InstallerWindow.qml" || rc=$?
    else
        qs -p "$SCRIPT_DIR/shell/InstallerWindow.qml" || rc=$?
    fi
    if [[ "$rc" -eq 0 ]]; then
        exit 0
    fi
    if [[ "$MODE" == "gui" ]]; then
        exit "$rc"
    fi
    echo "[paithosh] GUI installer exited ($rc) — falling back to CLI Installer..."
fi

echo "[paithosh] Launching CLI Installer..."
exec bash "$SCRIPT_DIR/installer/install_cli.sh" ${CLI_ARGS[@]+"${CLI_ARGS[@]}"}
