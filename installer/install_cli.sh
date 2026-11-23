#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/audit.sh
source "$SCRIPT_DIR/lib/audit.sh"

DRY_RUN="false"
[[ "${PAITHOSH_INSTALLER_DRY_RUN:-0}" == "1" ]] && DRY_RUN="true"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN="true"; shift ;;
        *) echo "[paithosh] Unknown option: $1" >&2; exit 2 ;;
    esac
done

if ! command -v python3 >/dev/null 2>&1; then
    echo "[paithosh] Error: python3 is required for the CLI installer." >&2
    exit 1
fi

BOLD="\033[1m"
DIM="\033[2m"
CYAN="\033[36m"
GREEN="\033[32m"
YELLOW="\033[33m"
RESET="\033[0m"

prompt_read() {
    local var_name="$1"
    local prompt_text="$2"
    local val=""
    if ! read -r -p "$prompt_text" val; then
        val=""
    fi
    printf -v "$var_name" '%s' "$val"
}

echo -e "${BOLD}${CYAN}=== Paithosh Shell Installer (TTY CLI Mode) ===${RESET}"
[[ "$DRY_RUN" == "true" ]] && echo -e "${YELLOW}[dry-run] Simulation mode active — no system changes will be made.${RESET}"

AUDIT_JSON="$(audit_json)"

eval "$(python3 - "$AUDIT_JSON" <<'PY'
import json, shlex, sys
d = json.loads(sys.argv[1])
dist = d["distro"]
cfg = d["configs"]
print(f"DISTRO_PRETTY={shlex.quote(dist['pretty'])}")
print(f"PKG_MGR={shlex.quote(dist['pkgMgr'])}")
print(f"COPR_NEEDED={'true' if dist.get('coprNeeded') else 'false'}")
print(f"AUR_WARNING={shlex.quote(dist.get('aurWarning', ''))}")
print(f"UNSUPPORTED_NOTE={shlex.quote(dist.get('unsupportedNote', ''))}")
print(f"HYPR_EXISTS={'true' if cfg['hyprExists'] else 'false'}")
print(f"HYPR_FILES={int(cfg['hyprFiles'])}")
print(f"HYPR_KIND={shlex.quote(cfg.get('hyprConfigKind', 'none'))}")
print(f"HYPR_MANAGED={'true' if cfg.get('hyprManagedByPaithosh') else 'false'}")
lua_sup = cfg.get('hyprLuaSupported')
print(f"HYPR_LUA_SUPPORTED={'true' if lua_sup is True else ('false' if lua_sup is False else 'unknown')}")

def split_unique(groups):
    seen = []
    for p in d["packages"]:
        if not p["installed"] and p["group"] in groups:
            for tok in p["pkg"].split():
                if tok not in seen:
                    seen.append(tok)
    return ",".join(seen)

print(f"MISSING_CORE={shlex.quote(split_unique({'core'}))}")
print(f"MISSING_REC={shlex.quote(split_unique({'core', 'wayland', 'system'}))}")
print(f"MISSING_ALL={shlex.quote(split_unique({'core', 'wayland', 'system', 'optional'}))}")
PY
)"

echo -e "Distro: ${BOLD}$DISTRO_PRETTY${RESET} (${DIM}$PKG_MGR${RESET})"
[[ "$COPR_NEEDED" == "true" ]] && echo -e "${CYAN}[i] Fedora COPR lionheartp/Hyprland will be enabled automatically if COPR packages are selected.${RESET}"
[[ -n "$AUR_WARNING" ]] && echo -e "${YELLOW}[!] $AUR_WARNING${RESET}"
[[ -n "$UNSUPPORTED_NOTE" ]] && echo -e "${YELLOW}[!] $UNSUPPORTED_NOTE${RESET}"
echo ""

# 1. Hyprland config check, backup & default Lua config sync
BACKUP_HYPR="false"
SYNC_HYPR="true"
if [[ "$HYPR_EXISTS" == "true" ]]; then
    echo -e "${YELLOW}${BOLD}[!] Existing ~/.config/hypr detected ($HYPR_FILES files, format: $HYPR_KIND${HYPR_MANAGED:+, managed: $HYPR_MANAGED}).${RESET}"
    echo -e "${DIM}    Paithosh can back up your existing ~/.config/hypr and replace it with Paithosh's modular Lua config.${RESET}"
    prompt_read s_ans "Replace ~/.config/hypr with Paithosh default Hyprland Lua config? [Y/n]: "
    [[ "${s_ans,,}" == "n" ]] && SYNC_HYPR="false"
    if [[ "$SYNC_HYPR" == "true" ]]; then
        prompt_read b_ans "Backup ~/.config/hypr before replacing? [Y/n]: "
    else
        prompt_read b_ans "Backup ~/.config/hypr before updating autostart? [Y/n]: "
    fi
    [[ "${b_ans,,}" != "n" ]] && BACKUP_HYPR="true"
else
    prompt_read s_ans "Install Paithosh default Hyprland Lua config to ~/.config/hypr? [Y/n]: "
    [[ "${s_ans,,}" == "n" ]] && SYNC_HYPR="false"
fi

if [[ "$SYNC_HYPR" == "true" && "$HYPR_LUA_SUPPORTED" == "false" ]]; then
    echo -e "${YELLOW}[!] Installed Hyprland binary does not appear to link liblua — Hyprland 0.57+ is required for Lua config.${RESET}"
fi
echo ""

# 2. Distro-filtered package audit
echo -e "${BOLD}System Package Audit:${RESET}"
python3 - "$AUDIT_JSON" <<'PY'
import json, sys
d = json.loads(sys.argv[1])
for p in d["packages"]:
    status = "\033[32m[OK]\033[0m" if p["installed"] else "\033[33m[MISSING]\033[0m"
    print(f"  {status} {p['label']:<28} ({p['group']:<8}) -> {p['pkg']}")
PY
echo ""

SELECTED_PKGS=""
if [[ -n "$MISSING_ALL" ]]; then
    echo "Select missing packages to install:"
    echo "  [1] Core + Recommended (Wayland & System controls)"
    echo "  [2] Core only"
    echo "  [3] All missing (including Optional)"
    echo "  [4] Skip package installation"
    prompt_read p_ans "Choice [1-4, default 1]: "
    case "${p_ans:-1}" in
        1) SELECTED_PKGS="$MISSING_REC" ;;
        2) SELECTED_PKGS="$MISSING_CORE" ;;
        3) SELECTED_PKGS="$MISSING_ALL" ;;
        *) SELECTED_PKGS="" ;;
    esac
    echo ""
fi

# 3. Multi-option preferences
echo "Theme Preset:"
echo "  [1] OLED Pure (default)"
echo "  [2] Nord Frost"
echo "  [3] Mica Dark"
echo "  [4] Adaptive"
echo "  [5] Mica Monochrome"
echo "  [6] Catppuccin Mocha"
prompt_read t_ans "Choice [1-6, default 1]: "
case "${t_ans:-1}" in
    2) THEME_PRESET="Nord Frost" ;;
    3) THEME_PRESET="Mica Dark" ;;
    4) THEME_PRESET="Adaptive" ;;
    5) THEME_PRESET="Mica Monochrome" ;;
    6) THEME_PRESET="Catppuccin Mocha" ;;
    *) THEME_PRESET="OLED Pure" ;;
esac

prompt_read b_pos "Bar position [top/bottom, default top]: "
BAR_POSITION="${b_pos,,}"
[[ "$BAR_POSITION" != "bottom" ]] && BAR_POSITION="top"

if [[ "$SYNC_HYPR" == "true" || "$HYPR_KIND" == "lua" ]]; then
    prompt_read a_ans "Add Paithosh autostart to Hyprland Lua config? [Y/n]: "
else
    prompt_read a_ans "Add Paithosh autostart (exec-once) to ~/.config/hypr/hyprland.conf? [Y/n]: "
fi
AUTOSTART="true"
[[ "${a_ans,,}" == "n" ]] && AUTOSTART="false"

prompt_read pt_ans "Configure XDG Desktop Portals (Screen Share & File Picker)? [Y/n]: "
SETUP_PORTALS="true"
[[ "${pt_ans,,}" == "n" ]] && SETUP_PORTALS="false"

echo ""
echo -e "${BOLD}Summary:${RESET}"
echo "  Backup ~/.config/hypr : $BACKUP_HYPR (format: $HYPR_KIND)"
echo "  Hyprland default sync : $SYNC_HYPR"
echo "  Packages to install   : ${SELECTED_PKGS:-none}"
echo "  Theme / Bar           : $THEME_PRESET / $BAR_POSITION"
echo "  Hyprland autostart    : $AUTOSTART"
echo "  XDG Desktop Portals   : $SETUP_PORTALS"
[[ "$DRY_RUN" == "true" ]] && echo "  Dry-run mode          : true (simulation)"
echo ""
prompt_read go_ans "Proceed with installation? [Y/n]: "
if [[ "${go_ans,,}" == "n" ]]; then
    echo "Cancelled."
    exit 0
fi

APPLY_ARGS=(
    --backup-hypr "$BACKUP_HYPR"
    --sync-hypr "$SYNC_HYPR"
    --packages "$SELECTED_PKGS"
    --theme "$THEME_PRESET"
    --bar-position "$BAR_POSITION"
    --autostart "$AUTOSTART"
    --setup-portals "$SETUP_PORTALS"
)
[[ "$DRY_RUN" == "true" ]] && APPLY_ARGS+=(--dry-run)

exec bash "$SCRIPT_DIR/lib/apply.sh" "${APPLY_ARGS[@]}"
