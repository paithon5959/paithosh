#!/usr/bin/env bash
set -euo pipefail

# Non-destructive demo & self-test runner for the Paithosh Installer.
# Usage:
#   ./installer/test_installer.sh --check
#   ./installer/test_installer.sh [--gui|--cli] [--os arch|fedora|debian|ubuntu] [--no-hypr]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

MODE="gui"
MOCK_OS=""
NO_HYPR="false"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --cli) MODE="cli"; shift ;;
        --gui) MODE="gui"; shift ;;
        --os) MOCK_OS="${2:-}"; shift 2 ;;
        --no-hypr) NO_HYPR="true"; shift ;;
        *) shift ;;
    esac
done

TMP_HOME=""
cleanup() {
    if [[ -n "$TMP_HOME" ]]; then
        rm -rf "$TMP_HOME"
    fi
}
trap cleanup EXIT

run_self_checks() {
    TMP_HOME="$(mktemp -d /tmp/paithosh-installer-check.XXXXXX)"

    echo "[1/6] Checking shell & Python script syntax..."
    local sh_files=(
        "$REPO_ROOT/install.sh"
        "$REPO_ROOT/installer/install_cli.sh"
        "$REPO_ROOT/installer/lib/audit.sh"
        "$REPO_ROOT/installer/lib/apply.sh"
        "$REPO_ROOT/installer/test_installer.sh"
        "$REPO_ROOT/shell/scripts/xdph-share-picker.sh"
        "$REPO_ROOT/shell/scripts/screen-record.sh"
    )
    for sf in "${sh_files[@]}"; do
        bash -n "$sf"
    done
    python3 -m py_compile "$REPO_ROOT/shell/scripts/paithosh-file-portal.py" "$REPO_ROOT/shell/scripts/paithosh-pak.py"
    echo "  PASS: syntax checks clean"

    echo "[2/6] Checking audit.sh JSON across arch/fedora/debian/ubuntu..."
    for os in arch fedora debian ubuntu; do
        local json_out
        json_out="$(HOME="$TMP_HOME" PAITHOSH_MOCK_OS="$os" bash "$REPO_ROOT/installer/lib/audit.sh" --json)"
        python3 - "$os" "$json_out" <<'PY'
import json, sys
os_name, raw = sys.argv[1], sys.argv[2]
d = json.loads(raw)
pkgs = {p["id"]: p for p in d["packages"]}
all_pkg_strs = [p["pkg"] for p in d["packages"]]

assert "wf-recorder" in pkgs, os_name
assert "pw-play" in pkgs, os_name
assert pkgs["wg-quick"]["group"] == "system", pkgs["wg-quick"]
assert "kdeconnectd" not in all_pkg_strs, all_pkg_strs
assert "policykit-1" not in all_pkg_strs, all_pkg_strs

if os_name == "fedora":
    assert pkgs["qt6-svg"]["pkg"] == "qt6-qtsvg"
    assert pkgs["kdeconnect-cli"]["pkg"] == "kde-connect"
    assert pkgs["pw-play"]["pkg"] == "pipewire-utils"
elif os_name == "arch":
    assert pkgs["qt6-svg"]["pkg"] == "qt6-svg"
    if d["distro"]["pkgMgr"] == "pacman":
        assert "quickshell-git" not in all_pkg_strs
        assert d["distro"]["aurWarning"]
elif os_name in ("debian", "ubuntu"):
    assert pkgs["qt6-svg"]["pkg"] == "qt6-svg-plugins"
    assert pkgs["pkexec"]["pkg"] == "pkexec"
    assert d["distro"]["unsupportedNote"]
PY
    done
    echo "  PASS: 4-distro audit mappings verified"

    echo "[3/6] Checking install_cli.sh --dry-run piped flow..."
    local cli_home="$TMP_HOME/cli"
    mkdir -p "$cli_home/.config/hypr/config"
    touch "$cli_home/.config/hypr/hyprland.lua" "$cli_home/.config/hypr/config/autostart.lua"
    local has_missing cli_in cli_out
    has_missing="$(HOME="$cli_home" bash "$REPO_ROOT/installer/lib/audit.sh" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print("1" if any(not p["installed"] for p in d["packages"]) else "0")')"
    if [[ "$has_missing" == "1" ]]; then
        cli_in=$'\n4\n2\nBOTTOM\ny\ny\ny\n'
    else
        cli_in=$'\n2\nBOTTOM\ny\ny\ny\n'
    fi
    cli_out="$(printf '%s' "$cli_in" | HOME="$cli_home" PAITHOSH_INSTALLER_DRY_RUN=1 bash "$REPO_ROOT/installer/install_cli.sh")"
    grep -q "Nord Frost" <<<"$cli_out"
    grep -q "barPosition=bottom" <<<"$cli_out"
    grep -q "Registering XDG Desktop Portals" <<<"$cli_out"
    echo "  PASS: CLI dry-run piped execution verified"

    echo "[4/6] Checking apply.sh Lua & .conf idempotency + XDG portals..."
    local lua_home="$TMP_HOME/lua"
    mkdir -p "$lua_home/.config/hypr/config"
    cat > "$lua_home/.config/hypr/hyprland.lua" <<'EOF'
require("config.autostart")
EOF
    cat > "$lua_home/.config/hypr/config/autostart.lua" <<'EOF'
hl.on("hyprland.start", function ()
    hl.exec_cmd("fcitx5 -d")
end)
EOF
    HOME="$lua_home" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --backup-hypr true --packages "" --theme "Nord Frost" \
        --bar-position bottom --autostart true --setup-portals true >/dev/null
    HOME="$lua_home" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --backup-hypr false --packages "" --theme "Nord Frost" \
        --bar-position bottom --autostart true --setup-portals true >/dev/null

    compgen -G "$lua_home/.config/hypr.bak.*" >/dev/null
    [[ ! -e "$lua_home/.config/hypr/hyprland.conf" ]]
    [[ "$(grep -c "qs -p " "$lua_home/.config/hypr/config/autostart.lua")" -eq 1 ]]
    python3 - "$lua_home/.config/paithosh/settings.json" <<'PY'
import json, sys
d = json.load(open(sys.argv[1]))
assert d["themePreset"] == "Nord Frost", d
assert d["barPosition"] == "bottom", d
assert d["globalSurfaceTheme"] == "Adaptive", d
PY
    [[ -L "$lua_home/.local/bin/hyprland-share-picker" ]]
    grep -Fq "$REPO_ROOT/shell/scripts/paithosh-file-portal.py" "$lua_home/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.paithosh.service"
    [[ -f "$lua_home/.local/share/xdg-desktop-portal/portals/paithosh.portal" ]]
    grep -Fq "org.freedesktop.impl.portal.FileChooser=paithosh" "$lua_home/.config/xdg-desktop-portal/hyprland-portals.conf"

    local conf_home="$TMP_HOME/conf"
    mkdir -p "$conf_home/.config/hypr"
    printf '# classic conf\n' > "$conf_home/.config/hypr/hyprland.conf"
    HOME="$conf_home" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --backup-hypr true --packages "" --theme "OLED Pure" \
        --bar-position top --autostart true --setup-portals true >/dev/null
    HOME="$conf_home" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --backup-hypr false --packages "" --theme "OLED Pure" \
        --bar-position top --autostart true --setup-portals true >/dev/null
    compgen -G "$conf_home/.config/hypr.bak.*" >/dev/null
    [[ "$(grep -c "exec-once = qs -p " "$conf_home/.config/hypr/hyprland.conf")" -eq 1 ]]
    echo "  PASS: Lua & classic .conf apply idempotency + XDG portals verified"

    echo "[5/6] Checking symlink resolution for xdph-share-picker.sh..."
    local resolved_qml
    resolved_qml="$(bash -c '
        SCRIPT_REAL="$(readlink -f "$1")"
        echo "$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)/shell.qml"
    ' _ "$lua_home/.local/bin/hyprland-share-picker")"
    [[ "$resolved_qml" == "$REPO_ROOT/shell/shell.qml" ]]
    grep -Fq 'readlink -f' "$REPO_ROOT/shell/scripts/xdph-share-picker.sh"
    echo "  PASS: symlink resolution verified"

    echo "[6/6] Checking curl-pipe bootstrap & self-clone flow..."
    local help_out
    help_out="$(cat "$REPO_ROOT/install.sh" | bash -s -- --help)"
    grep -Fq -- "--dir" <<<"$help_out"
    grep -Fq "curl -fsSL" <<<"$help_out"

    local current_branch
    current_branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)"

    local boot_home="$TMP_HOME/boot-home"
    mkdir -p "$boot_home"
    local boot_dir="$TMP_HOME/boot-repo"
    local boot_out1
    boot_out1="$(env \
        HOME="$boot_home" \
        WAYLAND_DISPLAY="" \
        PAITHOSH_NO_TTY_REATTACH=1 \
        PAITHOSH_REPO_URL="file://$REPO_ROOT" \
        PAITHOSH_BRANCH="$current_branch" \
        bash -s -- --dir "$boot_dir" --dry-run < "$REPO_ROOT/install.sh")"
    grep -Fq "Cloning Paithosh into $boot_dir" <<<"$boot_out1"
    grep -Fq "Installation complete!" <<<"$boot_out1"
    [[ -d "$boot_dir/.git" ]]

    local boot_out2
    boot_out2="$(env \
        HOME="$boot_home" \
        WAYLAND_DISPLAY="" \
        PAITHOSH_NO_TTY_REATTACH=1 \
        PAITHOSH_REPO_URL="file://$REPO_ROOT" \
        PAITHOSH_BRANCH="$current_branch" \
        bash -s -- --dir "$boot_dir" --dry-run < "$REPO_ROOT/install.sh")"
    grep -Fq "Updating Paithosh in $boot_dir" <<<"$boot_out2"
    grep -Fq "Installation complete!" <<<"$boot_out2"

    local dryrun_home="$TMP_HOME/boot-dryrun-home"
    mkdir -p "$dryrun_home"
    local dryrun_out
    dryrun_out="$(env \
        HOME="$dryrun_home" \
        WAYLAND_DISPLAY="" \
        PAITHOSH_NO_TTY_REATTACH=1 \
        PAITHOSH_REPO_URL="file://$REPO_ROOT" \
        PAITHOSH_BRANCH="$current_branch" \
        bash -s -- --dry-run < "$REPO_ROOT/install.sh")"
    grep -Fq "Installation complete!" <<<"$dryrun_out"
    [[ ! -e "$dryrun_home/.local/share/paithosh" ]]
    echo "  PASS: curl-pipe bootstrap & self-clone verified"

    echo "ALL INSTALLER CHECKS PASSED"
}

if [[ "$MODE" == "check" ]]; then
    run_self_checks
    exit 0
fi

if [[ "$NO_HYPR" == "true" || "$MODE" == "cli" ]]; then
    TMP_HOME="$(mktemp -d)"
    if [[ "$NO_HYPR" == "false" ]]; then
        mkdir -p "$TMP_HOME/.config/hypr"
        touch "$TMP_HOME/.config/hypr/hyprland.conf"
    fi
fi

ENV_ARGS=("PAITHOSH_INSTALLER_DRY_RUN=1")
[[ -n "$MOCK_OS" ]] && ENV_ARGS+=("PAITHOSH_MOCK_OS=$MOCK_OS")
[[ -n "$TMP_HOME" ]] && ENV_ARGS+=("HOME=$TMP_HOME")

if [[ "$MODE" == "cli" || ( -z "${WAYLAND_DISPLAY:-}" && -z "${DISPLAY:-}" ) ]]; then
    echo "[test] CLI dry-run (os=${MOCK_OS:-real}, no-hypr=$NO_HYPR)..."
    env "${ENV_ARGS[@]}" bash "$REPO_ROOT/installer/lib/audit.sh" --json | head -n 12
    env "${ENV_ARGS[@]}" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --dry-run \
        --backup-hypr "$([[ "$NO_HYPR" == "true" ]] && echo false || echo true)" \
        --packages "hyprlock,grim,slurp" \
        --theme "Nord Frost" \
        --bar-position top \
        --autostart true \
        --setup-portals true
    exit 0
fi

echo "[test] Launching GUI dry-run (os=${MOCK_OS:-real}, no-hypr=$NO_HYPR)..."
echo "[test] Press Esc or Close anytime to exit."
exec env "${ENV_ARGS[@]}" qs -p "$REPO_ROOT/shell/InstallerWindow.qml"
