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

    echo "[1/7] Checking shell & Python script syntax..."
    local sh_files=(
        "$REPO_ROOT/install.sh"
        "$REPO_ROOT/installer/install_cli.sh"
        "$REPO_ROOT/installer/lib/audit.sh"
        "$REPO_ROOT/installer/lib/apply.sh"
        "$REPO_ROOT/installer/lib/sync-hypr.sh"
        "$REPO_ROOT/installer/test_installer.sh"
        "$REPO_ROOT/shell/scripts/xdph-share-picker.sh"
        "$REPO_ROOT/shell/scripts/screen-record.sh"
    )
    for sf in "${sh_files[@]}"; do
        bash -n "$sf"
    done
    python3 -m py_compile "$REPO_ROOT/shell/scripts/paithosh-file-portal.py" "$REPO_ROOT/shell/scripts/paithosh-pak.py" "$REPO_ROOT/shell/scripts/paithosh-cursor-gen.py"
    echo "  PASS: syntax checks clean"

    echo "[2/7] Checking audit.sh JSON across arch/fedora/debian/ubuntu..."
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
assert "hyprcursor" in pkgs and pkgs["hyprcursor"]["group"] == "core" and pkgs["hyprcursor"].get("required") is True, pkgs.get("hyprcursor")
assert "cursor-render" in pkgs and pkgs["cursor-render"]["group"] == "core" and pkgs["cursor-render"].get("required") is True, pkgs.get("cursor-render")
assert pkgs["wg-quick"]["group"] == "system", pkgs["wg-quick"]
assert "kdeconnectd" not in all_pkg_strs, all_pkg_strs
assert "policykit-1" not in all_pkg_strs, all_pkg_strs

if os_name == "fedora":
    assert pkgs["qt6-svg"]["pkg"] == "qt6-qtsvg"
    assert pkgs["kdeconnect-cli"]["pkg"] == "kde-connect"
    assert pkgs["pw-play"]["pkg"] == "pipewire-utils"
    assert pkgs["hyprcursor"]["pkg"] == "hyprcursor"
    assert pkgs["cursor-render"]["pkg"] == "python3-cairo librsvg2"
elif os_name == "arch":
    assert pkgs["qt6-svg"]["pkg"] == "qt6-svg"
    assert pkgs["hyprcursor"]["pkg"] == "hyprcursor"
    assert pkgs["cursor-render"]["pkg"] == "python-cairo librsvg"
    if d["distro"]["pkgMgr"] == "pacman":
        assert "quickshell-git" not in all_pkg_strs
        assert d["distro"]["aurWarning"]
elif os_name in ("debian", "ubuntu"):
    assert pkgs["qt6-svg"]["pkg"] == "qt6-svg-plugins"
    assert pkgs["pkexec"]["pkg"] == "pkexec"
    assert pkgs["hyprcursor"]["pkg"] == "hyprcursor-util"
    assert pkgs["cursor-render"]["pkg"] == "python3-cairo gir1.2-rsvg-2.0"
    assert d["distro"]["unsupportedNote"]
PY
    done
    echo "  PASS: 4-distro audit mappings verified"

    echo "[3/7] Checking install_cli.sh --dry-run piped flow..."
    local cli_home="$TMP_HOME/cli"
    mkdir -p "$cli_home/.config/hypr/config"
    touch "$cli_home/.config/hypr/hyprland.lua" "$cli_home/.config/hypr/config/autostart.lua"
    local has_missing cli_in cli_out
    has_missing="$(HOME="$cli_home" bash "$REPO_ROOT/installer/lib/audit.sh" --json | python3 -c 'import json,sys; d=json.load(sys.stdin); print("1" if any((not p["installed"]) and (not p.get("required")) and p.get("group") != "core" for p in d["packages"]) else "0")')"
    if [[ "$has_missing" == "1" ]]; then
        cli_in=$'2\n\n\n3\n6\nBOTTOM\ny\ny\ny\n'
    else
        cli_in=$'2\n\n\n6\nBOTTOM\ny\ny\ny\n'
    fi
    cli_out="$(printf '%s' "$cli_in" | HOME="$cli_home" PAITHOSH_INSTALLER_DRY_RUN=1 bash "$REPO_ROOT/installer/install_cli.sh")"
    grep -q "Update stream         : release" <<<"$cli_out"
    grep -q "shellUpdateStream=release" <<<"$cli_out"
    grep -q "Hyprland default sync : true" <<<"$cli_out"
    grep -q "Catppuccin Mocha" <<<"$cli_out"
    grep -q "barPosition=bottom" <<<"$cli_out"
    grep -q "Registering XDG Desktop Portals" <<<"$cli_out"
    echo "  PASS: CLI dry-run piped execution verified"

    echo "[4/7] Checking apply.sh Lua & .conf idempotency + XDG portals..."
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
    [[ "$(grep -c "exec-once = QS_NO_RELOAD_POPUP=1 qs -p " "$conf_home/.config/hypr/hyprland.conf")" -eq 1 ]]

    local pkg_only_home="$TMP_HOME/pkgonly"
    mkdir -p "$pkg_only_home"
    HOME="$pkg_only_home" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --packages-only --dry-run --packages hyprcursor >/dev/null
    [[ ! -e "$pkg_only_home/.config/paithosh/settings.json" ]]
    echo "  PASS: Lua & classic .conf apply idempotency + XDG portals + packages-only verified"

    echo "[5/7] Checking symlink resolution for xdph-share-picker.sh..."
    local resolved_qml
    resolved_qml="$(bash -c '
        SCRIPT_REAL="$(readlink -f "$1")"
        echo "$(cd "$(dirname "$SCRIPT_REAL")/.." && pwd)/shell.qml"
    ' _ "$lua_home/.local/bin/hyprland-share-picker")"
    [[ "$resolved_qml" == "$REPO_ROOT/shell/shell.qml" ]]
    grep -Fq 'readlink -f' "$REPO_ROOT/shell/scripts/xdph-share-picker.sh"
    echo "  PASS: symlink resolution verified"

    echo "[6/7] Checking curl-pipe bootstrap & self-clone flow..."
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

    echo "[7/7] Checking sync-hypr.sh, --sync-hypr apply, Hyprland Lua config, KeybindService & shell updater..."
    local sync_home="$TMP_HOME/sync-home"
    mkdir -p "$sync_home"

    # 7a. Missing --repo-root value must exit 2 cleanly (not unbound variable)
    local rc=0
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root >/dev/null 2>&1 || rc=$?
    [[ "$rc" -eq 2 ]]

    # 7b. Status on missing config
    local st_missing
    st_missing="$(HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$REPO_ROOT" --status)"
    python3 -c 'import json,sys; d=json.loads(sys.argv[1]); assert d["state"]=="missing" and not d["managed"], d' "$st_missing"

    # 7c. Dry-run replace leaves filesystem clean
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$REPO_ROOT" --mode replace --dry-run --no-reload >/dev/null
    [[ ! -e "$sync_home/.config/hypr" ]]

    # 7d. Replace on fresh home + backup collision safety (2 calls in same second)
    local space_repo="$TMP_HOME/my repo"
    mkdir -p "$space_repo/defaults"
    cp -a "$REPO_ROOT/defaults/hypr" "$space_repo/defaults/hypr"
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode replace --no-reload >/dev/null
    [[ -f "$sync_home/.config/hypr/hyprland.lua" ]]
    [[ -f "$sync_home/.config/hypr/.paithosh-manifest" ]]
    grep -Fq 'root = "'"$space_repo"'"' "$sync_home/.config/hypr/config/paithosh.lua"

    # Replace twice rapidly -> collision-safe distinct backups
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode replace --no-reload >/dev/null
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode replace --no-reload >/dev/null
    local bkp_count
    bkp_count="$(find "$sync_home/.config" -maxdepth 1 -name 'hypr.bak.*' | wc -l | tr -d ' ')"
    [[ "$bkp_count" -ge 2 ]]

    # 7e. Staging validation failure preserves existing ~/.config/hypr untouched
    printf 'invalid lua syntax (\n' > "$space_repo/defaults/hypr/config/broken.lua"
    printf '%s\n' '-- sentinel' >> "$sync_home/.config/hypr/config/monitors.lua"
    rc=0
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode replace --no-reload >/dev/null 2>&1 || rc=$?
    [[ "$rc" -ne 0 ]]
    [[ ! -e "$sync_home/.config/hypr/config/broken.lua" ]]
    grep -Fq -- '-- sentinel' "$sync_home/.config/hypr/config/monitors.lua"
    rm -f "$space_repo/defaults/hypr/config/broken.lua"

    # 7f. 3-way manifest update: unmanaged skipped, managed preserves user edits + updates unmodified + adds new
    local unm_home="$TMP_HOME/unmanaged-home"
    mkdir -p "$unm_home/.config/hypr"
    printf '# my custom config\n' > "$unm_home/.config/hypr/hyprland.conf"
    HOME="$unm_home" XDG_CONFIG_HOME="$unm_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode update --no-reload >/dev/null
    [[ ! -e "$unm_home/.config/hypr/.paithosh-manifest" ]]
    grep -Fq '# my custom config' "$unm_home/.config/hypr/hyprland.conf"

    # Reset sync_home cleanly for managed update test
    rm -rf "$sync_home/.config/hypr" "$sync_home/.config/hypr.bak."*
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode replace --no-reload >/dev/null
    # Simulate user modifying monitors.lua, while upstream updates rules.lua and adds extra.lua
    printf '\n%s\n' '-- user custom monitor' >> "$sync_home/.config/hypr/config/monitors.lua"
    printf '\n%s\n' '-- upstream rule update' >> "$space_repo/defaults/hypr/config/rules.lua"
    printf '%s\n' '-- upstream new file' > "$space_repo/defaults/hypr/config/extra.lua"
    local st_outdated
    st_outdated="$(HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --status)"
    python3 - "$st_outdated" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
assert d["state"] == "outdated", d
assert "config/rules.lua" in d["updatedFiles"], d
assert "config/extra.lua" in d["addedFiles"], d
assert "config/monitors.lua" in d["modifiedFiles"], d
PY
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode update --no-reload >/dev/null
    grep -Fq -- '-- user custom monitor' "$sync_home/.config/hypr/config/monitors.lua"
    grep -Fq -- '-- upstream rule update' "$sync_home/.config/hypr/config/rules.lua"
    [[ -f "$sync_home/.config/hypr/config/extra.lua" ]]

    # Second update should be a no-op (no extra backup)
    local bkp_before bkp_after
    bkp_before="$(find "$sync_home/.config" -maxdepth 1 -name 'hypr.bak.*' | wc -l | tr -d ' ')"
    HOME="$sync_home" XDG_CONFIG_HOME="$sync_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$space_repo" --mode update --no-reload >/dev/null
    bkp_after="$(find "$sync_home/.config" -maxdepth 1 -name 'hypr.bak.*' | wc -l | tr -d ' ')"
    [[ "$bkp_before" -eq "$bkp_after" ]]

    # 7g. apply.sh --sync-hypr true + --backup-hypr true + --autostart true + custom XDG_CONFIG_HOME + INI [preferred]
    local apply_home="$TMP_HOME/apply-sync-home"
    local apply_xdg="$TMP_HOME/apply-xdg-cfg"
    mkdir -p "$apply_xdg/hypr" "$apply_xdg/xdg-desktop-portal"
    printf '# old conf\n' > "$apply_xdg/hypr/hyprland.conf"
    cat > "$apply_xdg/xdg-desktop-portal/hyprland-portals.conf" <<'EOF'
[preferred]
default=hyprland;gtk

[other]
foo=bar
EOF
    HOME="$apply_home" XDG_CONFIG_HOME="$apply_xdg" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --backup-hypr true --sync-hypr true --packages "" --theme "Catppuccin Mocha" \
        --bar-position top --autostart true --setup-portals true >/dev/null
    local apply_bkp_count
    apply_bkp_count="$(find "$apply_xdg" -maxdepth 1 -name 'hypr.bak.*' | wc -l | tr -d ' ')"
    [[ "$apply_bkp_count" -eq 1 ]]
    [[ ! -e "$apply_xdg/hypr/hyprland.conf" ]]
    [[ -f "$apply_xdg/hypr/config/paithosh.lua" ]]
    [[ -f "$apply_xdg/hypr/.paithosh-manifest" ]]
    [[ "$(grep -c 'qs -p ' "$apply_xdg/hypr/config/autostart.lua")" -eq 1 ]]
    python3 - "$apply_xdg/paithosh/settings.json" "$apply_xdg/xdg-desktop-portal/hyprland-portals.conf" <<'PY'
import json, sys
s = json.load(open(sys.argv[1]))
assert s["themePreset"] == "Catppuccin Mocha", s
assert s["globalSurfaceTheme"] == "Adaptive", s
portal_txt = open(sys.argv[2]).read()
pref, other = portal_txt.split("[other]", 1)
assert "org.freedesktop.impl.portal.FileChooser=paithosh" in pref, portal_txt
assert "org.freedesktop.impl.portal.FileChooser=paithosh" not in other, portal_txt
PY

    # 7h. apply.sh --sync-hypr true --autostart false disables qs -p in autostart.lua
    HOME="$apply_home" XDG_CONFIG_HOME="$apply_xdg" bash "$REPO_ROOT/installer/lib/apply.sh" \
        --backup-hypr false --sync-hypr true --packages "" --theme "OLED Pure" \
        --bar-position top --autostart false --setup-portals false >/dev/null
    grep -Eq '^[[:space:]]*--[[:space:]]*hl\.exec_cmd\(.*qs[[:space:]]+-p' "$apply_xdg/hypr/config/autostart.lua"

    # 7i. Hyprland --verify-config (if Hyprland with liblua is installed)
    if command -v Hyprland >/dev/null 2>&1 && ldd "$(command -v Hyprland)" 2>/dev/null | grep -qi 'liblua'; then
        local v_home="$TMP_HOME/verify-hypr"
        mkdir -p "$v_home/rt"
        chmod 700 "$v_home/rt"
        HOME="$v_home" XDG_CONFIG_HOME="$v_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$REPO_ROOT" --mode replace --no-reload >/dev/null
        local v_out
        v_out="$(XDG_RUNTIME_DIR="$v_home/rt" HOME="$v_home" XDG_CONFIG_HOME="$v_home/.config" Hyprland --verify-config -c "$v_home/.config/hypr/hyprland.lua" 2>&1 || true)"
        grep -Fq "config ok" <<<"$v_out"
    fi

    # 7j. PackageService.qml shellUpdateProc must NOT swallow git pull failures on dirty repo
    local git_test="$TMP_HOME/git-upd"
    mkdir -p "$git_test"
    git init -q --bare "$git_test/origin.git"
    git init -q "$git_test/work"
    git -C "$git_test/work" config user.email test@test
    git -C "$git_test/work" config user.name test
    mkdir -p "$git_test/work/installer/lib" "$git_test/work/defaults/hypr"
    cp -a "$REPO_ROOT/installer/lib/sync-hypr.sh" "$git_test/work/installer/lib/"
    cp -a "$REPO_ROOT/defaults/hypr/." "$git_test/work/defaults/hypr/"
    echo "v1" > "$git_test/work/README.md"
    git -C "$git_test/work" add . && git -C "$git_test/work" commit -q -m "init"
    git -C "$git_test/work" branch -M master
    git -C "$git_test/work" remote add origin "$git_test/origin.git"
    git -C "$git_test/work" push -q -u origin master
    git clone -q --no-local --depth 1 --branch master "file://$git_test/origin.git" "$git_test/local"
    echo "v2" > "$git_test/work/README.md"
    git -C "$git_test/work" commit -q -am "v2"
    git -C "$git_test/work" push -q origin master
    echo "dirty" > "$git_test/local/README.md"

    python3 - "$REPO_ROOT/shell/services/PackageService.qml" "$git_test/local" "$git_test/home" <<'PY'
import re, subprocess, sys
qml = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'id:\s*shellUpdateProc[\s\S]*?command:\s*\[\s*"sh",\s*"-c",\s*((?:"(?:[^"\\]|\\.)*"\s*\+\s*)*"(?:[^"\\]|\\.)*")', qml)
assert m, "Could not locate shellUpdateProc command in PackageService.qml"
parts = re.findall(r'"((?:[^"\\]|\\.)*)"', m.group(1))
script = bytes("".join(parts), "utf-8").decode("unicode_escape")
res = subprocess.run(
    ["sh", "-c", script, "sh", sys.argv[2]],
    env={"PATH": "/usr/local/bin:/usr/bin:/bin", "HOME": sys.argv[3]},
    capture_output=True, text=True
)
assert res.returncode != 0, f"Expected non-zero rc on dirty pull, got {res.returncode}, out={res.stdout}"
assert "error:" in res.stderr or "fatal:" in res.stderr or "Local modifications" in res.stderr, res.stderr
PY

    # 7k. KeybindService.qml parser classifies qsIpc binds from defaults/hypr/config/binds.lua
    #     and writeProc preserves custom Lua, mainMod, escapes quotes/backslashes, & guards syntax
    local kb_home="$TMP_HOME/kb-home"
    HOME="$kb_home" XDG_CONFIG_HOME="$kb_home/.config" bash "$REPO_ROOT/installer/lib/sync-hypr.sh" --repo-root "$REPO_ROOT" --mode replace --no-reload >/dev/null
    python3 - "$REPO_ROOT/shell/services/KeybindService.qml" "$kb_home" "$REPO_ROOT/shell" <<'PY'
import json, os, re, shutil, subprocess, sys
qml = open(sys.argv[1], encoding="utf-8").read()
m = re.search(r'id:\s*readProc\s*\n\s*command:\s*\["python3",\s*"-c",\s*`([\s\S]*?)`', qml)
assert m, "Could not locate readProc script in KeybindService.qml"
py_src = m.group(1).replace("\\\\", "\\")
mw = re.search(r'id:\s*writeProc[\s\S]*?command:\s*\["python3",\s*"-c",\s*`([\s\S]*?)`', qml)
assert mw, "Could not locate writeProc script in KeybindService.qml"
write_src = mw.group(1).replace("\\\\", "\\")

env = {"PATH": "/usr/local/bin:/usr/bin:/bin", "HOME": sys.argv[2]}
res = subprocess.run(
    ["python3", "-c", py_src, sys.argv[3]],
    env=env, capture_output=True, text=True, check=True
)
binds = json.loads(res.stdout)
cats = {}
titles = {b["title"]: b for b in binds}
for b in binds:
    cats[b["category"]] = cats.get(b["category"], 0) + 1
assert cats.get("island", 0) >= 8, cats
assert cats.get("screenshot", 0) >= 2, cats
assert "Clipboard History" in titles and titles["Clipboard History"]["category"] == "island", titles.keys()
assert "Screen Recording" in titles and titles["Screen Recording"]["category"] == "screenshot", titles.keys()
assert "Launcher & Bar Peek (Super Tap)" in titles, titles.keys()

binds_path = os.path.join(sys.argv[2], ".config", "hypr", "config", "binds.lua")
orig_txt = open(binds_path, encoding="utf-8").read()
orig_txt = orig_txt.replace('local mainMod  = "SUPER"', 'local mainMod  = "ALT"')
custom_block = '\n-- User custom snippet\nlocal myCustomFlag = 1\nhl.unbind("SUPER + Z")\nhl.bind("SUPER + mouse_down", hl.dsp.focus({ workspace = "e+1" }))\n'
open(binds_path, "w", encoding="utf-8").write(orig_txt + custom_block)

binds = json.loads(subprocess.check_output(["python3", "-c", py_src, sys.argv[3]], env=env, text=True))
m_sw = re.search(r'id:\s*"shotWindowClip".*?lua:\s*\'(.*?)\',\s*opts:', qml)
assert m_sw, "Could not locate shotWindowClip in KeybindService.qml"
sw_lua = m_sw.group(1).replace("\\'", "'").replace("\\\\", "\\")
binds.append({
    "id": "bind_test_sw",
    "category": "screenshot",
    "title": "Active Window → Clipboard",
    "subtitle": "grim + hyprctl",
    "actionType": "screenshot",
    "actionLua": sw_lua,
    "command": "",
    "appId": "",
    "groupTier": "core",
    "combos": [{"combo": "ALT + SHIFT + W", "opts": "", "release": False, "locked": False, "repeating": False}],
    "readOnly": False,
    "mainMod": "ALT",
})
binds.append({
    "id": "bind_test_esc",
    "category": "command",
    "title": 'echo "a\\b"',
    "subtitle": "",
    "actionType": "command",
    "actionLua": 'hl.dsp.exec_cmd("echo \\"a\\\\b\\"")',
    "command": 'echo "a\\b"',
    "appId": "",
    "groupTier": "core",
    "combos": [{"combo": "ALT + F9", "opts": "", "release": False, "locked": False, "repeating": False}],
    "readOnly": False,
    "mainMod": "ALT",
})

wres = subprocess.run(["python3", "-c", write_src, json.dumps(binds), sys.argv[3]], env=env, capture_output=True, text=True)
assert wres.returncode == 0 and wres.stdout.strip() == "ok", f"writeProc failed: {wres.stderr}"
written1 = open(binds_path, encoding="utf-8").read()
assert 'local mainMod  = "ALT"' in written1, "Lost custom mainMod"
assert "local myCustomFlag = 1" in written1, "Lost custom local variable"
assert 'hl.unbind("SUPER + Z")' in written1, "Lost hl.unbind"
assert "mouse_down" in written1, "Lost custom mouse_down bind"
if shutil.which("luajit"):
    subprocess.run(["luajit", "-bl", binds_path, "/dev/null"], check=True)

binds2 = json.loads(subprocess.check_output(["python3", "-c", py_src, sys.argv[3]], env=env, text=True))
assert any(b["command"] == 'echo "a\\b"' for b in binds2), "Escaped command round-trip mismatch"
subprocess.run(["python3", "-c", write_src, json.dumps(binds2), sys.argv[3]], env=env, check=True, capture_output=True, text=True)
written2 = open(binds_path, encoding="utf-8").read()
assert written1 == written2, "Second round-trip mutated binds.lua (not idempotent)"

bad_binds = list(binds2) + [{
    "id": "bind_bad",
    "category": "command",
    "title": "broken",
    "subtitle": "",
    "actionType": "command",
    "actionLua": 'hl.dsp.exec_cmd("unterminated',
    "command": "broken",
    "appId": "",
    "groupTier": "core",
    "combos": [{"combo": "ALT + F10", "opts": "", "release": False, "locked": False, "repeating": False}],
    "readOnly": False,
    "mainMod": "ALT",
}]
bad_res = subprocess.run(["python3", "-c", write_src, json.dumps(bad_binds), sys.argv[3]], env=env, capture_output=True, text=True)
if shutil.which("luajit") or shutil.which("luac") or shutil.which("lua"):
    assert bad_res.returncode != 0, "Expected invalid Lua syntax to be rejected"
    assert open(binds_path, encoding="utf-8").read() == written2, "binds.lua was modified despite Lua syntax failure"
PY
    echo "  PASS: sync-hypr.sh, Hyprland Lua verify, KeybindService & shell updater verified"

    echo "[8/8] Checking GUI installer post-install shell launch..."
    python3 - "$REPO_ROOT/shell/InstallerWindow.qml" "$TMP_HOME" <<'PY'
import os, re, stat, subprocess, sys

qml_path, tmp_home = sys.argv[1:3]
src = open(qml_path, "r", encoding="utf-8").read()

# 1. Finish button must invoke finishAndClose / closeInstaller rather than bare Qt.quit()
m_finish = re.search(r'text:\s*root\.installExitCode\s*===\s*0[^}]+?onClicked:\s*([^\n]+)', src, re.DOTALL)
if not m_finish:
    m_finish = re.search(r'text:\s*"Finish"[^}]+?onClicked:\s*([^\n]+)', src, re.DOTALL)
assert m_finish, "Could not locate Finish button in InstallerWindow.qml"
assert "Qt.quit()" not in m_finish.group(1), f"Finish button still calls bare Qt.quit(): {m_finish.group(1)}"

# 2. Must define detached post-install launcher guarded by !isDryRun and installExitCode === 0
m_fn = re.search(r'function\s+closeInstaller\s*\(\s*\)\s*\{.*?\n    \}', src, re.DOTALL)
assert m_fn, "Missing closeInstaller() helper in InstallerWindow.qml"
fn_body = m_fn.group(0)
assert "isDryRun" in fn_body, "closeInstaller() must not launch shell in dry-run mode"
assert "installDone" in fn_body and "installExitCode === 0" in fn_body, "closeInstaller() must only launch shell on successful install"
assert "Quickshell.execDetached" in fn_body and "setsid" in fn_body, "closeInstaller() must spawn detached setsid launcher"
assert "InstallerWindow" in fn_body, "Launcher must wait for InstallerWindow.qml to exit cleanly before pkill"
assert "QS_NO_RELOAD_POPUP=1" in fn_body and "qs -d -p" in fn_body, "Launcher must start qs -d -p with QS_NO_RELOAD_POPUP=1"
assert "hyprctl reload" in fn_body, "Launcher must reload Hyprland when config was synced"

# 3. Extract the sh -c payload and execute it with mock binaries
m_sh = re.search(r'"setsid",\s*"-f",\s*"sh",\s*"-c",\s*((?:"(?:[^"\\]|\\.)*"\s*\+?\s*)+),', fn_body, re.DOTALL)
assert m_sh, "Could not extract sh -c script from closeInstaller()"
parts = re.findall(r'"((?:[^"\\]|\\.)*)"', m_sh.group(1))
sh_script = "".join(bytes(p, "utf-8").decode("unicode_escape") for p in parts)

mock_bin = os.path.join(tmp_home, "mock-launch-bin")
os.makedirs(mock_bin, exist_ok=True)
log_file = os.path.join(tmp_home, "launch-trace.log")

def write_stub(name, body):
    p = os.path.join(mock_bin, name)
    with open(p, "w", encoding="utf-8") as f:
        f.write("#!/usr/bin/env bash\n" + body + "\n")
    os.chmod(p, os.stat(p).st_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)

write_stub("pgrep", "exit 1")
write_stub("pkill", "exit 0")
write_stub("hyprctl", f'echo "hyprctl:$*" >> "{log_file}"')
write_stub("qs", f'echo "qs:NO_POPUP=${{QS_NO_RELOAD_POPUP:-}}:$*" >> "{log_file}"')

base_env = os.environ.copy()
base_env["PATH"] = mock_bin + ":" + base_env.get("PATH", "")

# Case A: sync_hypr=1 in Hyprland session -> reloads Hyprland then starts qs -d -p
env_a = base_env.copy()
env_a["HYPRLAND_INSTANCE_SIGNATURE"] = "test-sig"
subprocess.run(["sh", "-c", sh_script, "_", "/fake/paithosh/shell", "1"], env=env_a, check=True)
trace_a = open(log_file, encoding="utf-8").read().splitlines()
assert trace_a == [
    "hyprctl:reload",
    "qs:NO_POPUP=1:-d -p /fake/paithosh/shell",
], f"Unexpected launch trace with sync_hypr=1: {trace_a}"

# Case B: sync_hypr=0 -> skips hyprctl reload, still starts qs -d -p
os.remove(log_file)
subprocess.run(["sh", "-c", sh_script, "_", "/fake/paithosh/shell", "0"], env=env_a, check=True)
trace_b = open(log_file, encoding="utf-8").read().splitlines()
assert trace_b == [
    "qs:NO_POPUP=1:-d -p /fake/paithosh/shell",
], f"Unexpected launch trace with sync_hypr=0: {trace_b}"
PY
    echo "  PASS: GUI installer post-install shell launch verified"

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
