#!/usr/bin/env bash
set -euo pipefail

BOOTSTRAP_TEMP_DIR=""
cleanup_bootstrap_temp() {
    if [[ -n "${BOOTSTRAP_TEMP_DIR:-}" && -d "${BOOTSTRAP_TEMP_DIR:-}" ]]; then
        rm -rf "$BOOTSTRAP_TEMP_DIR"
    fi
}
trap cleanup_bootstrap_temp EXIT

can_open_tty() {
    [[ "${PAITHOSH_NO_TTY_REATTACH:-0}" != "1" ]] && (: </dev/tty) 2>/dev/null
}

prompt_yn() {
    local prompt_text="$1"
    local ans="y"
    if [[ -t 0 ]]; then
        read -r -p "$prompt_text" ans || ans="n"
    elif can_open_tty; then
        read -r -p "$prompt_text" ans </dev/tty || ans="n"
    else
        ans="y"
    fi
    [[ "${ans,,}" != "n" ]]
}

run_priv() {
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif [[ -t 0 ]]; then
        sudo "$@"
    elif can_open_tty; then
        sudo "$@" </dev/tty
    elif sudo -n true 2>/dev/null; then
        sudo -n "$@"
    elif command -v pkexec >/dev/null 2>&1 && {
        local _uid
        _uid="$(id -u)"
        pgrep -u "$_uid" -x 'hyprpolkitagent|lxpolkit|xfce-polkit' >/dev/null 2>&1 ||
        pgrep -u "$_uid" -f '(^|/)(hyprpolkitagent|polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|polkit-mate-authentication-agent-1|lxpolkit|xfce-polkit)($|[[:space:]])' >/dev/null 2>&1
    }; then
        pkexec "$@"
    else
        echo "[paithosh] Privilege escalation requires a TTY, passwordless sudo, or active Polkit agent." >&2
        return 1
    fi
}

bootstrap_detect_pkg_mgr() {
    local id="" id_like=""
    case "${PAITHOSH_MOCK_OS:-}" in
        arch) id="arch" ;;
        fedora) id="fedora" ;;
        debian) id="debian" ;;
        ubuntu) id="ubuntu"; id_like="debian" ;;
        *)
            if [[ -r /etc/os-release ]]; then
                # shellcheck disable=SC1091
                source /etc/os-release
                id="${ID:-unknown}"
                id_like="${ID_LIKE:-}"
            fi
            ;;
    esac

    case " $id $id_like " in
        *" arch "*|*" cachyos "*|*" endeavouros "*|*" manjaro "*)
            echo "pacman"
            return 0
            ;;
        *" fedora "*|*" rhel "*|*" centos "*)
            if command -v dnf5 >/dev/null 2>&1; then
                echo "dnf5"
            else
                echo "dnf"
            fi
            return 0
            ;;
        *" debian "*|*" ubuntu "*|*" pop "*|*" linuxmint "*)
            echo "apt"
            return 0
            ;;
    esac

    if command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v dnf5 >/dev/null 2>&1; then
        echo "dnf5"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    else
        echo "unknown"
    fi
}

pacman_install() {
    if ! compgen -G "/var/lib/pacman/sync/*.db" >/dev/null 2>&1; then
        run_priv pacman -Syu --needed --noconfirm "$@"
    else
        run_priv pacman -S --needed --noconfirm "$@" || run_priv pacman -Syu --needed --noconfirm "$@"
    fi
}

ensure_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] git is missing; cannot clone repository in dry-run mode." >&2
        exit 1
    fi

    local mgr
    mgr="$(bootstrap_detect_pkg_mgr)"
    echo "[paithosh] git is required to download Paithosh."
    if ! prompt_yn "Install git now? [Y/n]: "; then
        echo "[paithosh] Cannot continue without git. Exiting." >&2
        exit 1
    fi

    case "$mgr" in
        pacman) pacman_install git ;;
        dnf|dnf5) run_priv "$mgr" install -y git ;;
        apt)
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get update
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get install -y git
            ;;
        *)
            echo "[paithosh] Unsupported package manager '$mgr'. Please install git manually." >&2
            exit 1
            ;;
    esac
}

bootstrap_and_reexec() {
    if [[ "${PAITHOSH_BOOTSTRAPPED:-0}" == "1" ]]; then
        echo "[paithosh] Error: installer files missing even after bootstrap." >&2
        exit 1
    fi

    local repo_url="${PAITHOSH_REPO_URL:-https://github.com/paithon5959/paithosh.git}"
    local repo_branch="${PAITHOSH_BRANCH:-master}"
    local target_dir=""
    local is_temp="false"

    if [[ -n "$CUSTOM_INSTALL_DIR" ]]; then
        target_dir="$CUSTOM_INSTALL_DIR"
    elif [[ -n "${PAITHOSH_INSTALL_DIR:-}" ]]; then
        target_dir="$PAITHOSH_INSTALL_DIR"
    elif [[ "$DRY_RUN" == "true" ]]; then
        BOOTSTRAP_TEMP_DIR="$(mktemp -d /tmp/paithosh-dryrun.XXXXXX)"
        target_dir="$BOOTSTRAP_TEMP_DIR/paithosh"
        is_temp="true"
    else
        target_dir="${XDG_DATA_HOME:-$HOME/.local/share}/paithosh"
    fi

    ensure_git

    if [[ -d "$target_dir/.git" ]]; then
        if [[ -z "$(git -C "$target_dir" status --porcelain 2>/dev/null || true)" ]]; then
            local cur_branch=""
            cur_branch="$(git -C "$target_dir" symbolic-ref --short HEAD 2>/dev/null || true)"
            if [[ -z "$cur_branch" ]]; then
                echo "[paithosh] Existing checkout in $target_dir is on a release tag (detached HEAD); fetching tags..."
                git -C "$target_dir" fetch --tags --quiet origin 2>/dev/null || true
            else
                echo "[paithosh] Updating Paithosh in $target_dir..."
                if ! git -C "$target_dir" pull --ff-only origin "$repo_branch"; then
                    echo "[paithosh] Warning: could not fast-forward update $target_dir; using existing checkout." >&2
                fi
            fi
        else
            echo "[paithosh] Existing checkout in $target_dir has local modifications; preserving it."
        fi
    elif [[ -d "$target_dir" ]] && [[ -n "$(ls -A "$target_dir" 2>/dev/null || true)" ]]; then
        if [[ -f "$target_dir/install.sh" && -f "$target_dir/installer/lib/audit.sh" ]]; then
            echo "[paithosh] Reusing existing directory $target_dir..."
        else
            echo "[paithosh] Error: target directory '$target_dir' exists and is not empty. Specify another directory with --dir <path> or PAITHOSH_INSTALL_DIR." >&2
            exit 1
        fi
    else
        mkdir -p "$(dirname "$target_dir")"
        echo "[paithosh] Cloning Paithosh into $target_dir..."
        git clone --branch "$repo_branch" "$repo_url" "$target_dir"
    fi

    if [[ ! -f "$target_dir/install.sh" || ! -f "$target_dir/installer/lib/audit.sh" ]]; then
        echo "[paithosh] Error: cloned repository at '$target_dir' is missing installer files." >&2
        exit 1
    fi

    if [[ "$is_temp" == "true" ]]; then
        local rc=0
        if [[ ! -t 0 ]] && can_open_tty; then
            env PAITHOSH_BOOTSTRAPPED=1 bash "$target_dir/install.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"} </dev/tty || rc=$?
        else
            env PAITHOSH_BOOTSTRAPPED=1 bash "$target_dir/install.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"} || rc=$?
        fi
        exit "$rc"
    fi

    if [[ ! -t 0 ]] && can_open_tty; then
        exec env PAITHOSH_BOOTSTRAPPED=1 bash "$target_dir/install.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"} </dev/tty
    else
        exec env PAITHOSH_BOOTSTRAPPED=1 bash "$target_dir/install.sh" ${FORWARD_ARGS[@]+"${FORWARD_ARGS[@]}"}
    fi
}

can_run_gui() {
    [[ -n "${WAYLAND_DISPLAY:-}" ]] || return 1
    [[ "${XDG_CURRENT_DESKTOP:-}" != *[Gg][Nn][Oo][Mm][Ee]* ]] || return 1
    return 0
}

ensure_python3() {
    if command -v python3 >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] python3 is required but not installed." >&2
        exit 1
    fi
    echo "[paithosh] Python 3 is required by the Paithosh installer."
    echo "[paithosh] Detected: $PRETTY_NAME ($PKG_MGR)"
    if ! prompt_yn "Install Python 3 now? [Y/n]: "; then
        echo "[paithosh] Cannot continue without python3. Exiting." >&2
        exit 1
    fi
    if [[ "$FAMILY" == "arch" ]]; then
        pacman_install python
        return $?
    fi
    case "$PKG_MGR" in
        dnf|dnf5) run_priv "$PKG_MGR" install -y python3 ;;
        apt)
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get update
            run_priv env DEBIAN_FRONTEND=noninteractive apt-get install -y python3
            ;;
        *)
            echo "[paithosh] Unsupported package manager '$PKG_MGR'. Please install python3 manually." >&2
            exit 1
            ;;
    esac
}

ensure_quickshell() {
    if command -v qs >/dev/null 2>&1 || command -v quickshell >/dev/null 2>&1; then
        return 0
    fi
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Quickshell (qs) is not installed; skipping package install in dry-run." >&2
        return 1
    fi

    echo "[paithosh] Quickshell (qs) is needed for the GUI installer."
    echo "[paithosh] Detected: $PRETTY_NAME ($PKG_MGR)"
    if ! prompt_yn "Install Quickshell now? [Y/n]: "; then
        return 1
    fi

    case "$PKG_MGR" in
        pacman)
            echo "[paithosh] Trying quickshell via pacman (install paru/yay for quickshell-git if unavailable)..."
            pacman_install quickshell || return 1
            ;;
        paru|yay)
            if [[ "$EUID" -eq 0 ]]; then
                echo "[paithosh] Warning: AUR helper '$PKG_MGR' cannot run as root. Install quickshell-git as a non-root user." >&2
                return 1
            fi
            local -a aur_args=(-S --needed --noconfirm --sudoloop)
            if ! compgen -G "/var/lib/pacman/sync/*.db" >/dev/null 2>&1; then
                aur_args=(-Syu --needed --noconfirm --sudoloop)
            fi
            local qs_pkg="quickshell-git"
            if pacman -Si quickshell >/dev/null 2>&1; then
                qs_pkg="quickshell"
            fi
            if [[ ! -t 0 ]] && can_open_tty; then
                "$PKG_MGR" "${aur_args[@]}" "$qs_pkg" </dev/tty || return 1
            else
                "$PKG_MGR" "${aur_args[@]}" "$qs_pkg" || return 1
            fi
            ;;
        dnf|dnf5)
            if ! fedora_hypr_copr_enabled; then
                echo "[paithosh] Enabling Fedora COPR lionheartp/Hyprland..."
                run_priv sh -c 'mgr="$1"; "$mgr" copr enable -y lionheartp/Hyprland && exec "$mgr" install -y quickshell' _ "$PKG_MGR" || return 1
            else
                run_priv "$PKG_MGR" install -y quickshell || return 1
            fi
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

    if ! command -v qs >/dev/null 2>&1 && ! command -v quickshell >/dev/null 2>&1; then
        echo "[paithosh] Warning: Quickshell installation completed but 'qs' binary was not found." >&2
        return 1
    fi
}

main() {
    MODE="auto"
    DRY_RUN="false"
    CUSTOM_INSTALL_DIR=""
    FORWARD_ARGS=()

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --cli) MODE="cli"; FORWARD_ARGS+=("--cli"); shift ;;
            --gui) MODE="gui"; FORWARD_ARGS+=("--gui"); shift ;;
            --dry-run) DRY_RUN="true"; FORWARD_ARGS+=("--dry-run"); shift ;;
            --dir)
                if [[ $# -lt 2 || -z "$2" ]]; then
                    echo "[paithosh] Missing value for option '--dir'" >&2
                    exit 2
                fi
                CUSTOM_INSTALL_DIR="$2"
                shift 2
                ;;
            -h|--help)
                cat <<'EOF'
Usage: ./install.sh [--gui|--cli] [--dry-run] [--dir <path>]
  curl -fsSL https://raw.githubusercontent.com/paithon5959/paithosh/master/install.sh | bash

  --gui         Force Quickshell Wayland GUI installer
  --cli         Force TTY CLI installer
  --dry-run     Simulate installation without modifying the system
  --dir <path>  Clone/update Paithosh in <path> instead of ~/.local/share/paithosh
EOF
                exit 0
                ;;
            *) echo "[paithosh] Unknown option: $1 (see --help)" >&2; exit 2 ;;
        esac
    done

    local source_path="${BASH_SOURCE[0]:-}"
    SCRIPT_DIR=""
    if [[ -n "$source_path" && -f "$source_path" ]]; then
        SCRIPT_DIR="$(cd "$(dirname "$source_path")" && pwd)"
    fi

    if [[ -z "$SCRIPT_DIR" || ! -f "$SCRIPT_DIR/installer/lib/audit.sh" || ! -f "$SCRIPT_DIR/installer/install_cli.sh" ]]; then
        bootstrap_and_reexec
    elif [[ -n "$CUSTOM_INSTALL_DIR" && "${PAITHOSH_BOOTSTRAPPED:-0}" != "1" ]]; then
        local resolved_custom=""
        if command -v realpath >/dev/null 2>&1; then
            resolved_custom="$(realpath -m "$CUSTOM_INSTALL_DIR")"
        elif [[ -d "$CUSTOM_INSTALL_DIR" ]]; then
            resolved_custom="$(cd "$CUSTOM_INSTALL_DIR" && pwd)"
        else
            resolved_custom="${CUSTOM_INSTALL_DIR%/}"
        fi
        if [[ "$resolved_custom" != "$SCRIPT_DIR" ]]; then
            bootstrap_and_reexec
        fi
    fi

    # shellcheck source=installer/lib/audit.sh
    source "$SCRIPT_DIR/installer/lib/audit.sh"

    IFS='|' read -r DISTRO_ID FAMILY PKG_MGR PRETTY_NAME <<<"$(detect_distro)"

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
        local qs_bin="qs"
        command -v qs >/dev/null 2>&1 || qs_bin="quickshell"
        GUI_ENV=("QS_DISABLE_FILE_WATCHER=1" "QS_NO_RELOAD_POPUP=1")
        [[ "$DRY_RUN" == "true" || "${PAITHOSH_INSTALLER_DRY_RUN:-0}" == "1" ]] && GUI_ENV+=("PAITHOSH_INSTALLER_DRY_RUN=1")
        local rc=0
        env "${GUI_ENV[@]}" "$qs_bin" -p "$SCRIPT_DIR/shell/InstallerWindow.qml" || rc=$?
        if [[ "$rc" -eq 0 ]]; then
            exit 0
        fi
        if [[ "$MODE" == "gui" ]]; then
            exit "$rc"
        fi
        echo "[paithosh] GUI installer exited ($rc) — falling back to CLI Installer..."
    fi

    echo "[paithosh] Launching CLI Installer..."
    if [[ ! -t 0 ]] && can_open_tty; then
        exec bash "$SCRIPT_DIR/installer/install_cli.sh" ${CLI_ARGS[@]+"${CLI_ARGS[@]}"} </dev/tty
    else
        exec bash "$SCRIPT_DIR/installer/install_cli.sh" ${CLI_ARGS[@]+"${CLI_ARGS[@]}"}
    fi
}

main "$@"
