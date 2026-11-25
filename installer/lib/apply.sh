#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
# shellcheck source=./audit.sh
source "$SCRIPT_DIR/audit.sh"

BACKUP_HYPR="false"
SYNC_HYPR="false"
INSTALL_PKGS=""
THEME_PRESET="OLED Pure"
BAR_POSITION="top"
AUTOSTART="true"
SETUP_PORTALS="true"
SUDO_STDIN="false"
DRY_RUN="false"
PACKAGES_ONLY="false"

require_arg() {
    if [[ "$1" -lt 2 ]]; then
        echo "[paithosh] Missing value for option '$2'" >&2
        exit 2
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --backup-hypr) require_arg $# "$1"; BACKUP_HYPR="$2"; shift 2 ;;
        --sync-hypr) require_arg $# "$1"; SYNC_HYPR="$2"; shift 2 ;;
        --packages) require_arg $# "$1"; INSTALL_PKGS="$2"; shift 2 ;;
        --theme) require_arg $# "$1"; THEME_PRESET="$2"; shift 2 ;;
        --bar-position) require_arg $# "$1"; BAR_POSITION="$2"; shift 2 ;;
        --autostart) require_arg $# "$1"; AUTOSTART="$2"; shift 2 ;;
        --setup-portals) require_arg $# "$1"; SETUP_PORTALS="$2"; shift 2 ;;
        --sudo-stdin) SUDO_STDIN="true"; shift ;;
        --dry-run) DRY_RUN="true"; shift ;;
        --packages-only) PACKAGES_ONLY="true"; shift ;;
        *) echo "[paithosh] Unknown option: $1" >&2; exit 2 ;;
    esac
done

BAR_POSITION="${BAR_POSITION,,}"
[[ "$BAR_POSITION" != "bottom" ]] && BAR_POSITION="top"

SUDO_PWD=""
ASKPASS_DIR=""
cleanup() {
    unset SUDO_PWD || true
    if [[ -n "${ASKPASS_DIR:-}" && -d "${ASKPASS_DIR:-}" ]]; then
        rm -rf "$ASKPASS_DIR"
    fi
}
trap cleanup EXIT

emit_step() {
    printf 'STEP|%s|%s\n' "$1" "$2"
}

run_cmd() {
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] $*"
        sleep 0.15
    else
        "$@"
    fi
}

run_privileged() {
    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd sudo "$@"
        return 0
    fi
    if [[ "$EUID" -eq 0 ]]; then
        "$@"
    elif [[ "$SUDO_STDIN" == "true" ]]; then
        printf '%s\n' "$SUDO_PWD" | sudo -S -p "" "$@"
    elif [[ -t 0 ]]; then
        sudo "$@"
    elif sudo -n true 2>/dev/null; then
        sudo -n "$@"
    elif command -v pkexec >/dev/null 2>&1 && pgrep -f 'polkit.*agent|polkit-gnome|hyprpolkitagent|lxpolkit|mate-polkit|xfce-polkit' >/dev/null 2>&1; then
        pkexec "$@"
    else
        echo "[paithosh] Privilege escalation requires a TTY, active Polkit agent, or --sudo-stdin." >&2
        return 1
    fi
}

run_aur_helper() {
    local helper="$1"
    shift
    if [[ "$DRY_RUN" == "true" ]]; then
        run_cmd "$helper" "$@"
        return 0
    fi
    if [[ "$EUID" -eq 0 ]]; then
        echo "[paithosh] AUR helper ($helper) cannot run as root." >&2
        return 1
    fi
    if [[ "$SUDO_STDIN" == "true" ]]; then
        if [[ -z "$ASKPASS_DIR" ]]; then
            ASKPASS_DIR="$(mktemp -d)"
            chmod 700 "$ASKPASS_DIR"
            printf '%s\n' "$SUDO_PWD" > "$ASKPASS_DIR/pw"
            chmod 600 "$ASKPASS_DIR/pw"
            cat > "$ASKPASS_DIR/askpass.sh" <<'EOF'
#!/usr/bin/env sh
cat "$(dirname "$0")/pw"
EOF
            chmod 700 "$ASKPASS_DIR/askpass.sh"
        fi
        SUDO_ASKPASS="$ASKPASS_DIR/askpass.sh" "$helper" --sudoflags "-A" "$@"
    elif [[ -t 0 ]] || sudo -n true 2>/dev/null; then
        "$helper" "$@"
    else
        echo "[paithosh] AUR helper ($helper) requires a TTY or --sudo-stdin." >&2
        return 1
    fi
}

IFS='|' read -r DISTRO_ID FAMILY PKG_MGR PRETTY_NAME <<<"$(detect_distro)"
echo "[paithosh] Distro: $PRETTY_NAME ($FAMILY / $PKG_MGR)"

# Sanitize & deduplicate selected packages (handles comma or space separated tokens)
declare -a PKG_LIST=()
declare -A _SEEN_PKG=()
for raw_tok in ${INSTALL_PKGS//,/ }; do
    if [[ "$raw_tok" =~ ^[a-zA-Z0-9][a-zA-Z0-9._+-]*$ ]] && [[ -z "${_SEEN_PKG[$raw_tok]:-}" ]]; then
        _SEEN_PKG["$raw_tok"]=1
        PKG_LIST+=("$raw_tok")
    fi
done

if [[ "$SUDO_STDIN" == "true" ]]; then
    IFS= read -r SUDO_PWD || true
    if [[ ${#PKG_LIST[@]} -gt 0 && "$DRY_RUN" != "true" && "$EUID" -ne 0 ]]; then
        if ! printf '%s\n' "$SUDO_PWD" | sudo -S -k -v -p "" >/dev/null 2>&1; then
            echo "[paithosh] Incorrect sudo password." >&2
            exit 42
        fi
    fi
fi

CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"

# 1. Backup existing ~/.config/hypr if requested
if [[ "$PACKAGES_ONLY" != "true" ]]; then
    emit_step "1/6" "Checking Hyprland configuration backup..."
    HYPR_DIR="${CONFIG_HOME}/hypr"
    DID_BACKUP="false"
    HYPR_HAS_CONTENT="false"
    if [[ -L "$HYPR_DIR" ]]; then
        HYPR_HAS_CONTENT="true"
    elif [[ -d "$HYPR_DIR" ]] && [[ -n "$(find -L "$HYPR_DIR" -maxdepth 3 -type f -print -quit 2>/dev/null)" ]]; then
        HYPR_HAS_CONTENT="true"
    elif [[ -e "$HYPR_DIR" && ! -d "$HYPR_DIR" ]]; then
        HYPR_HAS_CONTENT="true"
    fi

    if [[ "$BACKUP_HYPR" == "true" && "$HYPR_HAS_CONTENT" == "true" ]]; then
        TS="$(date +%Y%m%d_%H%M%S)"
        BACKUP_BASE="${CONFIG_HOME}/hypr.bak.${TS}"
        BACKUP_PATH="$BACKUP_BASE"
        BKP_IDX=1
        while [[ -e "$BACKUP_PATH" || -L "$BACKUP_PATH" ]]; do
            BACKUP_PATH="${BACKUP_BASE}.${BKP_IDX}"
            BKP_IDX=$((BKP_IDX + 1))
        done
        echo "[paithosh] Backing up $HYPR_DIR -> $BACKUP_PATH"
        run_cmd cp -a "$HYPR_DIR" "$BACKUP_PATH"
        DID_BACKUP="true"
    fi
fi

# 2. Install selected missing packages using distro-appropriate package manager
emit_step "2/6" "Installing selected system packages..."
if [[ ${#PKG_LIST[@]} -gt 0 ]]; then
    echo "[paithosh] Installing packages (${#PKG_LIST[@]}): ${PKG_LIST[*]}"
    if [[ "$FAMILY" == "fedora" ]]; then
        for pkg in "${PKG_LIST[@]}"; do
            case "$pkg" in
                quickshell|hyprland|hyprcursor|hyprlock|hyprpolkitagent|xdg-desktop-portal-hyprland)
                    if ! grep -qs "enabled=1" /etc/yum.repos.d/*copr*[Hh]yprland*.repo 2>/dev/null; then
                        echo "[paithosh] Enabling Fedora COPR lionheartp/Hyprland..."
                        run_privileged "$PKG_MGR" copr enable -y lionheartp/Hyprland
                    fi
                    break
                    ;;
            esac
        done
    fi

    INSTALL_MGR="$PKG_MGR"
    if [[ "$EUID" -eq 0 && ( "$INSTALL_MGR" == "paru" || "$INSTALL_MGR" == "yay" ) ]]; then
        INSTALL_MGR="pacman"
    fi

    case "$INSTALL_MGR" in
        pacman)
            if ! compgen -G "/var/lib/pacman/sync/*.db" >/dev/null 2>&1; then
                run_privileged pacman -Sy --needed --noconfirm "${PKG_LIST[@]}"
            else
                run_privileged pacman -S --needed --noconfirm "${PKG_LIST[@]}"
            fi
            ;;
        paru)
            if [[ ! -t 0 ]]; then
                run_aur_helper paru -S --needed --noconfirm --skipreview "${PKG_LIST[@]}"
            else
                run_aur_helper paru -S --needed --noconfirm "${PKG_LIST[@]}"
            fi
            ;;
        yay)
            if [[ ! -t 0 ]]; then
                run_aur_helper yay -S --needed --noconfirm --answerdiff None --answerclean None "${PKG_LIST[@]}"
            else
                run_aur_helper yay -S --needed --noconfirm "${PKG_LIST[@]}"
            fi
            ;;
        dnf|dnf5) run_privileged "$PKG_MGR" install -y "${PKG_LIST[@]}" ;;
        apt)
            run_privileged env DEBIAN_FRONTEND=noninteractive apt-get update
            run_privileged env DEBIAN_FRONTEND=noninteractive apt-get install -y "${PKG_LIST[@]}"
            ;;
        *)
            echo "[paithosh] Unsupported package manager '$PKG_MGR' — cannot install: ${PKG_LIST[*]}" >&2
            exit 1
            ;;
    esac
else
    echo "[paithosh] No packages selected for installation."
fi

if [[ "$PACKAGES_ONLY" == "true" ]]; then
    echo "[paithosh] Required packages step complete."
    exit 0
fi

# 3. Create Paithosh directories & initial settings
emit_step "3/6" "Writing Paithosh settings & directories..."
PAITHOSH_DIR="${CONFIG_HOME}/paithosh"
SHOTS_DIR="${HOME}/Pictures/Screenshots"
run_cmd mkdir -p "$PAITHOSH_DIR" "$SHOTS_DIR"

SETTINGS_FILE="${PAITHOSH_DIR}/settings.json"
if [[ "$DRY_RUN" == "true" ]]; then
    echo "[dry-run] Write $SETTINGS_FILE (theme=$THEME_PRESET, barPosition=$BAR_POSITION)"
else
    python3 - "$SETTINGS_FILE" "$THEME_PRESET" "$BAR_POSITION" <<'PY'
import json, os, sys
path, theme, pos = sys.argv[1:4]
surface_map = {
    "OLED Pure": "OLED Pure",
    "Nord Frost": "Adaptive",
    "Mica Monochrome": "Mica Dark",
    "Mica Dark": "Mica Dark",
    "Adaptive": "Adaptive",
    "Catppuccin Mocha": "Adaptive",
}
data = {}
if os.path.exists(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                data = loaded
    except Exception:
        data = {}
data["themePreset"] = theme
data["barPosition"] = pos
if theme in surface_map:
    data["globalSurfaceTheme"] = surface_map[theme]
with open(path, "w", encoding="utf-8") as f:
    json.dump(data, f, indent=2)
    f.write("\n")
print(f"[paithosh] Saved {path}")
PY
    if command -v hyprcursor-util >/dev/null 2>&1 && [[ -f "${REPO_ROOT}/shell/scripts/paithosh-cursor-gen.py" ]]; then
        python3 "${REPO_ROOT}/shell/scripts/paithosh-cursor-gen.py" apply --style sharp --size 24 --color-mode auto --no-live >/dev/null 2>&1 || true
    fi
fi

# 4. Sync default Hyprland Lua configuration if requested
emit_step "4/6" "Syncing default Hyprland configuration..."
if [[ "$SYNC_HYPR" == "true" ]]; then
    SYNC_ARGS=(--repo-root "$REPO_ROOT" --mode replace --no-reload)
    [[ "$DRY_RUN" == "true" ]] && SYNC_ARGS+=(--dry-run)
    if [[ "$DID_BACKUP" == "true" || "$BACKUP_HYPR" != "true" ]]; then
        SYNC_ARGS+=(--no-backup)
    fi
    bash "$SCRIPT_DIR/sync-hypr.sh" "${SYNC_ARGS[@]}"
else
    echo "[paithosh] Skipping default Hyprland config sync (keeping existing config)."
fi

# 5. Hyprland autostart integration (supports both Hyprland Lua & classic .conf)
emit_step "5/6" "Configuring Hyprland autostart..."
AUTOSTART_LUA="${HYPR_DIR}/config/autostart.lua"
HYPR_LUA="${HYPR_DIR}/hyprland.lua"
HYPR_CONF="${HYPR_DIR}/hyprland.conf"

has_paithosh_launch() {
    local f="$1"
    [[ -f "$f" ]] || return 1
    if grep -Eq 'qs[[:space:]]+-p[[:space:]]+.*(paithosh/shell|shell/shell\.qml|paithosh\.root)' "$f"; then
        return 0
    fi
    if grep -Eq 'qs[[:space:]]+-p' "$f" && grep -Fq "${REPO_ROOT}/shell" "$f"; then
        return 0
    fi
    return 1
}

if [[ "$AUTOSTART" == "true" ]]; then
    _sq="'"
    if [[ "$REPO_ROOT" == *[[:space:]"$_sq"\"\\]* ]]; then
        escaped_shell_arg="${_sq}${REPO_ROOT//"$_sq"/"$_sq\\$_sq$_sq"}/shell${_sq}"
        SHELL_CMD="QS_NO_RELOAD_POPUP=1 qs -p ${escaped_shell_arg}"
    else
        SHELL_CMD="QS_NO_RELOAD_POPUP=1 qs -p ${REPO_ROOT}/shell"
    fi

    if [[ "$DRY_RUN" == "true" && "$SYNC_HYPR" == "true" ]]; then
        echo "[dry-run] Hyprland Lua autostart already provided by synced config/autostart.lua"
    elif [[ -f "$AUTOSTART_LUA" ]]; then
        if has_paithosh_launch "$AUTOSTART_LUA"; then
            echo "[paithosh] Autostart already present in $AUTOSTART_LUA"
        elif [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Ensure hl.exec_cmd(\"$SHELL_CMD\") in $AUTOSTART_LUA"
        else
            python3 - "$AUTOSTART_LUA" "$SHELL_CMD" <<'PY'
import re, sys
path, cmd = sys.argv[1:3]
txt = open(path, "r", encoding="utf-8").read()
lua_cmd = cmd.replace("\\", "\\\\").replace('"', '\\"')
line = f'    hl.exec_cmd("{lua_cmd}")'
hm = re.search(r'hl\.on\(\s*["\']hyprland\.start["\']', txt)
m = re.search(r'(?m)^([ \t]*)end\)', txt[hm.end():]) if hm else None
if hm and m:
    idx = hm.end() + m.start()
    new_txt = txt[:idx] + line + "\n" + txt[idx:]
else:
    sep = "" if (not txt or txt.endswith("\n")) else "\n"
    new_txt = txt + f'{sep}\n-- Paithosh Shell\nhl.on("hyprland.start", function()\n{line}\nend)\n'
with open(path, "w", encoding="utf-8") as f:
    f.write(new_txt)
PY
            echo "[paithosh] Added autostart to $AUTOSTART_LUA"
        fi
    elif [[ -f "$HYPR_LUA" ]]; then
        if has_paithosh_launch "$HYPR_LUA"; then
            echo "[paithosh] Autostart already present in $HYPR_LUA"
        elif [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Ensure hl.exec_cmd(\"$SHELL_CMD\") in $HYPR_LUA"
        else
            python3 - "$HYPR_LUA" "$SHELL_CMD" <<'PY'
import sys
path, cmd = sys.argv[1:3]
txt = open(path, "r", encoding="utf-8").read()
lua_cmd = cmd.replace("\\", "\\\\").replace('"', '\\"')
sep = "" if (not txt or txt.endswith("\n")) else "\n"
with open(path, "w", encoding="utf-8") as f:
    f.write(txt + f'{sep}\n-- Paithosh Shell\nhl.on("hyprland.start", function()\n    hl.exec_cmd("{lua_cmd}")\nend)\n')
PY
            echo "[paithosh] Added autostart to $HYPR_LUA"
        fi
    else
        EXEC_LINE="exec-once = ${SHELL_CMD}"
        if [[ "$DRY_RUN" == "true" ]]; then
            echo "[dry-run] Ensure '$EXEC_LINE' in $HYPR_CONF"
        else
            mkdir -p "$HYPR_DIR"
            touch "$HYPR_CONF"
            if ! has_paithosh_launch "$HYPR_CONF"; then
                printf '\n# Paithosh Shell\n%s\n' "$EXEC_LINE" >> "$HYPR_CONF"
                echo "[paithosh] Added autostart to $HYPR_CONF"
            else
                echo "[paithosh] Autostart already present in $HYPR_CONF"
            fi
        fi
    fi
elif [[ "$SYNC_HYPR" == "true" ]]; then
    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Would disable qs -p autostart in $AUTOSTART_LUA"
    elif [[ -f "$AUTOSTART_LUA" ]]; then
        python3 - "$AUTOSTART_LUA" <<'PY'
import re, sys
path = sys.argv[1]
txt = open(path, "r", encoding="utf-8").read()
out_lines = []
changed = False
for line in txt.splitlines(keepends=True):
    if not line.lstrip().startswith("--") and re.search(r'hl\.exec_cmd\(.*qs\s+-p', line):
        indent = line[:len(line) - len(line.lstrip())]
        out_lines.append(indent + "-- " + line.lstrip())
        changed = True
    else:
        out_lines.append(line)
if changed:
    with open(path, "w", encoding="utf-8") as f:
        f.write("".join(out_lines))
PY
        echo "[paithosh] Disabled autostart in $AUTOSTART_LUA as requested."
    fi
fi

# 6. XDG Desktop Portals (Screen Share picker + FileChooser D-Bus service)
emit_step "6/6" "Registering XDG Desktop Portals..."
if [[ "$SETUP_PORTALS" == "true" ]]; then
    LOCAL_BIN="${HOME}/.local/bin"
    DBUS_DIR="${HOME}/.local/share/dbus-1/services"
    PORTALS_DIR="${HOME}/.local/share/xdg-desktop-portal/portals"
    XDP_CFG_DIR="${CONFIG_HOME}/xdg-desktop-portal"
    PORTALS_CONF="${XDP_CFG_DIR}/hyprland-portals.conf"

    if [[ "$DRY_RUN" == "true" ]]; then
        echo "[dry-run] Symlink ${LOCAL_BIN}/hyprland-share-picker -> ${REPO_ROOT}/shell/scripts/xdph-share-picker.sh"
        echo "[dry-run] Write ${DBUS_DIR}/org.freedesktop.impl.portal.desktop.paithosh.service"
        echo "[dry-run] Write ${PORTALS_DIR}/paithosh.portal"
        echo "[dry-run] Ensure FileChooser=paithosh in ${PORTALS_CONF}"
    else
        mkdir -p "$LOCAL_BIN" "$DBUS_DIR" "$PORTALS_DIR" "$XDP_CFG_DIR"
        ln -sf "${REPO_ROOT}/shell/scripts/xdph-share-picker.sh" "${LOCAL_BIN}/hyprland-share-picker"

        cat > "${DBUS_DIR}/org.freedesktop.impl.portal.desktop.paithosh.service" <<EOF
[D-BUS Service]
Name=org.freedesktop.impl.portal.desktop.paithosh
Exec=${REPO_ROOT}/shell/scripts/paithosh-file-portal.py
EOF

        cat > "${PORTALS_DIR}/paithosh.portal" <<'EOF'
[portal]
DBusName=org.freedesktop.impl.portal.desktop.paithosh
Interfaces=org.freedesktop.impl.portal.FileChooser;
UseIn=Hyprland;hyprland
EOF

        python3 - "$PORTALS_CONF" <<'PY'
import os, re, sys

conf_path = sys.argv[1]
target_line = "org.freedesktop.impl.portal.FileChooser=paithosh\n"

if not os.path.exists(conf_path):
    with open(conf_path, "w", encoding="utf-8") as f:
        f.write("[preferred]\ndefault=hyprland;gtk\n" + target_line)
    sys.exit(0)

with open(conf_path, "r", encoding="utf-8") as f:
    lines = f.readlines()

pref_start = None
pref_end = len(lines)
for idx, ln in enumerate(lines):
    s = ln.strip()
    if pref_start is None:
        if re.match(r'^\[preferred\]\s*(#.*)?$', s, re.IGNORECASE):
            pref_start = idx
    elif s.startswith("[") and "]" in s:
        pref_end = idx
        break

if pref_start is None:
    if lines and not lines[-1].endswith("\n"):
        lines[-1] += "\n"
    if lines and lines[-1].strip() != "":
        lines.append("\n")
    lines.extend(["[preferred]\n", "default=hyprland;gtk\n", target_line])
else:
    replaced = False
    for idx in range(pref_start + 1, pref_end):
        if re.match(r'^\s*org\.freedesktop\.impl\.portal\.FileChooser\s*=', lines[idx]):
            lines[idx] = target_line
            replaced = True
            break
    if not replaced:
        insert_at = pref_end
        while insert_at > pref_start + 1 and lines[insert_at - 1].strip() == "":
            insert_at -= 1
        if insert_at > 0 and not lines[insert_at - 1].endswith("\n"):
            lines[insert_at - 1] += "\n"
        lines.insert(insert_at, target_line)

with open(conf_path, "w", encoding="utf-8") as f:
    f.writelines(lines)
PY
        echo "[paithosh] XDG Desktop Portals configured."
    fi
fi

echo "[paithosh] Installation complete!"
