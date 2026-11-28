#!/usr/bin/env bash
set -euo pipefail
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

LOCK_FILE="/run/paithosh-btrfs.lock"
REGISTRY_DIR="/var/lib/paithosh"
REGISTRY_FILE="/var/lib/paithosh/snapshots.json"
SNAP_SUBDIR="@paithosh-snapshots"
TOP_MNT=""

step() {
    local name="$1" status="$2" detail="$3"
    detail="${detail//$'\r'/ }"
    detail="${detail//$'\n'/ }"
    printf 'STEP|%s|%s|%s\n' "$name" "$status" "$detail"
}

result_json() {
    printf 'RESULT|%s\n' "$1"
}

fail_json() {
    local msg="$1"
    step "error" "fail" "$msg"
    python3 -c 'import json, sys; print("RESULT|" + json.dumps({"ok": False, "error": sys.argv[1]}, ensure_ascii=False))' "$msg"
    exit 1
}

cleanup_top() {
    if [ -n "${TOP_MNT:-}" ]; then
        umount "$TOP_MNT" 2>/dev/null || true
        rmdir "$TOP_MNT" 2>/dev/null || true
        TOP_MNT=""
    fi
}
trap cleanup_top EXIT INT TERM

validate_id() {
    local id="$1"
    if [[ ! "$id" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        fail_json "Invalid snapshot ID: $id"
    fi
}

require_root() {
    if [ "$(id -u)" -ne 0 ]; then
        fail_json "Root privileges required for Btrfs operation"
    fi
}

detect_btrfs_env() {
    ROOT_FSTYPE=$(findmnt -n -v -o FSTYPE / 2>/dev/null || true)
    ROOT_SOURCE=$(findmnt -n -v -o SOURCE / 2>/dev/null || true)
    ROOT_FSROOT=$(findmnt -n -v -o FSROOT / 2>/dev/null || true)
    ROOT_OPTS=$(findmnt -n -v -o OPTIONS / 2>/dev/null || true)
    ROOT_DEV="${ROOT_SOURCE%%\[*}"
    ROOT_SUBVOL="${ROOT_FSROOT#/}"
    if [ -z "$ROOT_SUBVOL" ] && [[ "$ROOT_OPTS" =~ subvol=([^,]+) ]]; then
        ROOT_SUBVOL="${BASH_REMATCH[1]#/}"
    fi
    ROOT_UUID=$(findmnt -n -v -o UUID / 2>/dev/null || true)
    if [ -z "$ROOT_UUID" ] && [ -n "$ROOT_DEV" ]; then
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEV" 2>/dev/null || true)
    fi

    HOME_SOURCE=$(findmnt -n -v -o SOURCE /home 2>/dev/null || true)
    HOME_FSROOT=$(findmnt -n -v -o FSROOT /home 2>/dev/null || true)
    HOME_SEPARATE=0
    if findmnt -n /home >/dev/null 2>&1; then
        if [ "$HOME_SOURCE" != "$ROOT_SOURCE" ] || [ "$HOME_FSROOT" != "$ROOT_FSROOT" ]; then
            HOME_SEPARATE=1
        fi
    fi

    BOOT_FSTYPE=$(findmnt -n -v -o FSTYPE /boot 2>/dev/null || true)
    BOOT_SEPARATE=0
    if [ -n "$BOOT_FSTYPE" ]; then
        BOOT_SEPARATE=1
    fi

    KERNEL_RUNNING=$(uname -r)
    VMLINUZ_EXISTS=0
    [ -f "/boot/vmlinuz-$KERNEL_RUNNING" ] && VMLINUZ_EXISTS=1
    INITRAMFS_EXISTS=0
    if [ -f "/boot/initramfs-$KERNEL_RUNNING.img" ] || [ -f "/boot/initramfs-$KERNEL_RUNNING" ]; then
        INITRAMFS_EXISTS=1
    fi

    POLKIT_ACTIVE=0
    local uid
    uid=$(id -u)
    if pgrep -u "$uid" -x 'hyprpolkitagent|lxpolkit|xfce-polkit' >/dev/null 2>&1 ||
       pgrep -u "$uid" -f '(^|/)(hyprpolkitagent|polkit-gnome-authentication-agent-1|polkit-kde-authentication-agent-1|polkit-mate-authentication-agent-1|lxpolkit|xfce-polkit)($|[[:space:]])' >/dev/null 2>&1; then
        POLKIT_ACTIVE=1
    fi

    BOOT_ID=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo "")

    local df_line
    df_line=$(df -B1 --output=pcent,avail / 2>/dev/null | tail -n1 || echo "0% 0")
    DISK_USED_PCT=$(echo "$df_line" | awk '{gsub("%","",$1); print $1+0}')
    DISK_AVAIL_BYTES=$(echo "$df_line" | awk '{print $2+0}')

    IS_BTRFS_ROOT=0
    if [ "$ROOT_FSTYPE" = "btrfs" ] && [ -n "$ROOT_SUBVOL" ] && [ -n "$ROOT_UUID" ]; then
        IS_BTRFS_ROOT=1
    fi

    LEGACY_NESTED_COUNT=0
    if [ -d "/.snapshots/paithosh" ]; then
        LEGACY_NESTED_COUNT=$(find "/.snapshots/paithosh" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l || echo 0)
    fi
}

mount_top_level() {
    require_root
    [ "$IS_BTRFS_ROOT" -eq 1 ] || fail_json "Root (/) is not a named Btrfs subvolume (fstype=$ROOT_FSTYPE, subvol=$ROOT_SUBVOL)"
    mkdir -p /run
    exec 9>"$LOCK_FILE"
    flock -w 15 9 || fail_json "Could not acquire Btrfs lock ($LOCK_FILE)"
    TOP_MNT=$(mktemp -d /run/paithosh-btrfs-top.XXXXXX)
    mount -t btrfs -o subvolid=5 "UUID=$ROOT_UUID" "$TOP_MNT" || fail_json "Failed to mount Btrfs top-level subvolid=5 (UUID=$ROOT_UUID)"
}

parse_btrfs_show() {
    local snap_path="$1"
    local raw
    raw=$(btrfs subvolume show "$snap_path" 2>&1) || return 1
    python3 -c '
import json, sys
text = sys.stdin.read()
info = {"uuid": "", "parentUuid": "", "subvolId": 0, "readOnly": False, "name": ""}
for line in text.splitlines():
    if ":" not in line:
        continue
    k, v = [p.strip() for p in line.split(":", 1)]
    low = k.lower()
    if low == "name":
        info["name"] = v
    elif low == "uuid":
        info["uuid"] = v
    elif low == "parent uuid":
        info["parentUuid"] = "" if v == "-" else v
    elif low == "subvolume id":
        try: info["subvolId"] = int(v)
        except ValueError: pass
    elif low == "flags":
        info["readOnly"] = ("readonly" in v.lower())
print(json.dumps(info))
' <<<"$raw"
}

find_matched_kernels() {
    local snap_path="$1"
    local preferred_req="${2:-}"
    python3 -c '
import glob, json, os, sys
snap, pref = sys.argv[1], sys.argv[2]
mod_dirs = []
for base in ("usr/lib/modules", "lib/modules"):
    p = os.path.join(snap, base)
    if os.path.isdir(p):
        try:
            for d in os.listdir(p):
                if os.path.isdir(os.path.join(p, d)) and d not in mod_dirs:
                    mod_dirs.append(d)
        except OSError:
            pass
matched = []
for k in sorted(mod_dirs):
    if os.path.isfile(f"/boot/vmlinuz-{k}"):
        matched.append(k)
chosen = ""
if pref and pref in matched:
    chosen = pref
elif matched:
    chosen = matched[-1]
print(json.dumps({"snapshotKernels": sorted(mod_dirs), "matchedKernels": matched, "preferredKernel": chosen}))
' "$snap_path" "$preferred_req"
}

cmd_probe() {
    local sys_dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --sys-dir) sys_dir="$2"; shift 2 ;;
            *) fail_json "Unknown probe arg: $1" ;;
        esac
    done
    detect_btrfs_env

    local json_out
    json_out=$(python3 -c '
import datetime, glob, json, os, sys

sys_dir = sys.argv[1]
reg_file = sys.argv[2]
boot_id = sys.argv[3]
env = {
    "isBtrfsRoot": sys.argv[4] == "1",
    "rootFstype": sys.argv[5],
    "rootDevice": sys.argv[6],
    "rootUuid": sys.argv[7],
    "rootSubvol": sys.argv[8],
    "homeSeparateSubvol": sys.argv[9] == "1",
    "bootSeparate": sys.argv[10] == "1",
    "bootFstype": sys.argv[11],
    "kernelRunning": sys.argv[12],
    "vmlinuzExists": sys.argv[13] == "1",
    "initramfsExists": sys.argv[14] == "1",
    "polkitAgentActive": sys.argv[15] == "1",
    "diskUsedPct": int(sys.argv[16] or 0),
    "diskAvailBytes": int(sys.argv[17] or 0),
    "legacyNestedCount": int(sys.argv[18] or 0),
    "registryPath": reg_file,
    "snapshotTopDir": "@paithosh-snapshots",
}

reg = {"snapshots": {}, "staged_rollback": None}
if os.path.isfile(reg_file):
    try:
        with open(reg_file, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                if isinstance(loaded.get("snapshots"), dict):
                    reg["snapshots"] = loaded["snapshots"]
                reg["staged_rollback"] = loaded.get("staged_rollback")
    except Exception:
        pass

staged = reg.get("staged_rollback")
if isinstance(staged, dict) and staged.get("boot_id") and boot_id and staged.get("boot_id") != boot_id:
    staged = None

by_id = {}

# Load from root-verified registry first
for sid, rec in reg["snapshots"].items():
    if not isinstance(rec, dict):
        continue
    b = rec.get("btrfs") or {}
    arc = rec.get("archive") or {}
    by_id[sid] = {
        "id": sid,
        "name": arc.get("name") or f"{sid}.tar.gz",
        "path": arc.get("path") or (os.path.join(sys_dir, f"{sid}.tar.gz") if sys_dir else ""),
        "metaPath": os.path.join(sys_dir, f"{sid}.meta.json") if sys_dir else "",
        "createdAt": rec.get("created_at") or "",
        "mtime": rec.get("mtime") or 0,
        "dateText": rec.get("date_text") or "",
        "sizeBytes": int(arc.get("size_bytes") or 0),
        "reason": rec.get("reason") or "",
        "trigger": rec.get("trigger") or "manual",
        "hasBtrfsSnap": bool(b.get("created")),
        "btrfsVerified": bool(b.get("verified")),
        "btrfsUuid": b.get("uuid") or "",
        "subvolId": int(b.get("subvol_id") or 0),
        "readOnly": bool(b.get("read_only")),
        "snapshotSubvol": b.get("subvol_path") or f"@paithosh-snapshots/{sid}",
        "kernel": rec.get("kernel") or "",
        "archiveSha256": arc.get("sha256") or "",
        "steps": rec.get("steps") or [],
        "isPreRollback": bool(rec.get("is_pre_rollback")),
        "etcBackedUpCount": int(rec.get("etc_backed_up_count") or 0),
        "etcSkippedCount": int(rec.get("etc_skipped_count") or 0),
    }

# Merge user-space archive / meta.json files
if sys_dir and os.path.isdir(sys_dir):
    meta_paths = glob.glob(os.path.join(sys_dir, "*.meta.json"))
    tar_paths = glob.glob(os.path.join(sys_dir, "*.tar.gz"))
    all_ids = set()
    for p in meta_paths:
        all_ids.add(os.path.basename(p)[:-10])
    for p in tar_paths:
        all_ids.add(os.path.basename(p)[:-7])

    for sid in all_ids:
        meta_p = os.path.join(sys_dir, f"{sid}.meta.json")
        tar_p = os.path.join(sys_dir, f"{sid}.tar.gz")
        meta = {}
        if os.path.isfile(meta_p):
            try:
                with open(meta_p, "r", encoding="utf-8") as f:
                    loaded = json.load(f)
                    if isinstance(loaded, dict):
                        meta = loaded
            except Exception:
                meta = {}
        st = None
        for probe_p in (tar_p, meta_p):
            if os.path.isfile(probe_p):
                try:
                    st = os.stat(probe_p)
                    break
                except OSError:
                    pass
        size_bytes = os.path.getsize(tar_p) if os.path.isfile(tar_p) else 0
        mtime = st.st_mtime if st else 0
        dt_text = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M") if mtime else ""

        if sid in by_id:
            item = by_id[sid]
            if os.path.isfile(tar_p):
                item["path"] = tar_p
                item["name"] = os.path.basename(tar_p)
                item["sizeBytes"] = size_bytes
            if mtime and not item["mtime"]:
                item["mtime"] = mtime
            if dt_text and not item["dateText"]:
                item["dateText"] = dt_text
            continue

        b_meta = meta.get("btrfs") if isinstance(meta.get("btrfs"), dict) else {}
        a_meta = meta.get("archive") if isinstance(meta.get("archive"), dict) else {}
        boot_meta = meta.get("boot") if isinstance(meta.get("boot"), dict) else {}
        by_id[sid] = {
            "id": sid,
            "name": os.path.basename(tar_p) if os.path.isfile(tar_p) else sid,
            "path": tar_p if os.path.isfile(tar_p) else meta_p,
            "metaPath": meta_p if os.path.isfile(meta_p) else "",
            "createdAt": meta.get("date") or "",
            "mtime": mtime,
            "dateText": dt_text,
            "sizeBytes": size_bytes,
            "reason": meta.get("reason") or "",
            "trigger": meta.get("trigger") or "manual",
            "hasBtrfsSnap": bool(b_meta.get("created")),
            "btrfsVerified": bool(b_meta.get("verified")),
            "btrfsUuid": b_meta.get("uuid") or "",
            "subvolId": int(b_meta.get("subvol_id") or 0),
            "readOnly": bool(b_meta.get("read_only")),
            "snapshotSubvol": b_meta.get("subvol_path") or "",
            "kernel": boot_meta.get("kernel") or "",
            "archiveSha256": a_meta.get("sha256") or "",
            "steps": meta.get("steps") or [],
            "isPreRollback": False,
            "etcBackedUpCount": len(a_meta.get("etc_backed_up") or []),
            "etcSkippedCount": len(a_meta.get("etc_skipped") or []),
        }

items = list(by_id.values())
for it in items:
    if not it["dateText"] and it["createdAt"]:
        try:
            it["dateText"] = datetime.datetime.fromisoformat(it["createdAt"]).strftime("%Y-%m-%d %H:%M")
        except Exception:
            it["dateText"] = it["createdAt"][:16]
    if not it["mtime"] and it["createdAt"]:
        try:
            it["mtime"] = datetime.datetime.fromisoformat(it["createdAt"]).timestamp()
        except Exception:
            it["mtime"] = 0

items.sort(key=lambda x: float(x.get("mtime") or 0), reverse=True)
print(json.dumps({"ok": True, "env": env, "stagedRollback": staged, "snapshots": items}, ensure_ascii=False))
' "$sys_dir" "$REGISTRY_FILE" "$BOOT_ID" "$IS_BTRFS_ROOT" "$ROOT_FSTYPE" "$ROOT_DEV" "$ROOT_UUID" "$ROOT_SUBVOL" "$HOME_SEPARATE" "$BOOT_SEPARATE" "$BOOT_FSTYPE" "$KERNEL_RUNNING" "$VMLINUZ_EXISTS" "$INITRAMFS_EXISTS" "$POLKIT_ACTIVE" "$DISK_USED_PCT" "$DISK_AVAIL_BYTES" "$LEGACY_NESTED_COUNT")
    result_json "$json_out"
}

cmd_create() {
    local id="" reason="Manual system backup" trigger="manual" sys_dir="" home_dir="" with_btrfs="1" emit_result="1"
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            --reason) reason="$2"; shift 2 ;;
            --trigger) trigger="$2"; shift 2 ;;
            --sys-dir) sys_dir="$2"; shift 2 ;;
            --home-dir) home_dir="$2"; shift 2 ;;
            --with-btrfs) with_btrfs="$2"; shift 2 ;;
            --no-result) emit_result="0"; shift ;;
            *) fail_json "Unknown create arg: $1" ;;
        esac
    done
    [ -n "$id" ] || fail_json "Missing --id"
    [ -n "$sys_dir" ] || fail_json "Missing --sys-dir"
    [ -n "$home_dir" ] || fail_json "Missing --home-dir"
    validate_id "$id"

    detect_btrfs_env
    local steps_json="[]"
    add_step_json() {
        local st_name="$1" st_status="$2" st_detail="$3"
        step "$st_name" "$st_status" "$st_detail"
        steps_json=$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); a.append({"step":sys.argv[2],"status":sys.argv[3],"detail":sys.argv[4]}); print(json.dumps(a,ensure_ascii=False))' "$steps_json" "$st_name" "$st_status" "$st_detail")
    }

    local btrfs_created="0" btrfs_verified="0" btrfs_uuid="" btrfs_parent_uuid="" btrfs_subvol_id="0" btrfs_ro="0" snap_rel="$SNAP_SUBDIR/$id"

    if [ "$with_btrfs" = "1" ]; then
        require_root
        mount_top_level
        mkdir -p "$TOP_MNT/$SNAP_SUBDIR"
        local snap_full="$TOP_MNT/$snap_rel"
        if [ -e "$snap_full" ]; then
            fail_json "Snapshot $snap_rel already exists"
        fi
        add_step_json "btrfs_mount" "ok" "Mounted top-level Btrfs subvolid=5 ($ROOT_DEV)"

        if ! btrfs subvolume snapshot -r "$TOP_MNT/$ROOT_SUBVOL" "$snap_full" >/dev/null 2>&1; then
            fail_json "btrfs subvolume snapshot failed for $ROOT_SUBVOL -> $snap_rel"
        fi
        btrfs_created="1"

        local show_json
        if ! show_json=$(parse_btrfs_show "$snap_full"); then
            fail_json "btrfs subvolume show verification failed on $snap_rel"
        fi
        btrfs_uuid=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["uuid"])' "$show_json")
        btrfs_parent_uuid=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["parentUuid"])' "$show_json")
        btrfs_subvol_id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["subvolId"])' "$show_json")
        btrfs_ro=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1])["readOnly"] else "0")' "$show_json")

        [ "$btrfs_ro" = "1" ] || fail_json "Snapshot $snap_rel is not marked read-only"
        [ -n "$btrfs_uuid" ] || fail_json "Snapshot $snap_rel has empty Btrfs UUID"
        [ -f "$snap_full/etc/fstab" ] || fail_json "Snapshot $snap_rel missing /etc/fstab marker"
        [ -f "$snap_full/usr/lib/os-release" ] || [ -f "$snap_full/etc/os-release" ] || fail_json "Snapshot $snap_rel missing os-release marker"
        btrfs_verified="1"
        add_step_json "btrfs_snapshot" "ok" "Verified read-only snapshot $snap_rel (UUID ${btrfs_uuid:0:8}..., ID $btrfs_subvol_id)"

        if [ "$VMLINUZ_EXISTS" -eq 1 ]; then
            add_step_json "boot_check" "ok" "Matched running kernel $KERNEL_RUNNING in /boot"
        else
            add_step_json "boot_check" "warn" "Running kernel $KERNEL_RUNNING not found in /boot"
        fi
        cleanup_top
    else
        add_step_json "btrfs_snapshot" "warn" "Btrfs snapshot disabled — creating package & config archive only"
    fi

    mkdir -p "$sys_dir"
    local stage
    stage=$(mktemp -d)
    local etc_stage="$stage/etc-files"
    mkdir -p "$etc_stage"

    if command -v rpm >/dev/null 2>&1; then
        rpm -qa --qf '%{NAME}\t%{EVR}\t%{ARCH}\n' 2>/dev/null | sort > "$stage/packages.txt" || true
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Q 2>/dev/null > "$stage/packages.txt" || true
    elif command -v dpkg-query >/dev/null 2>&1; then
        dpkg-query -W -f='${Package}\t${Version}\t${Architecture}\n' 2>/dev/null | sort > "$stage/packages.txt" || true
    fi

    if command -v dnf5 >/dev/null 2>&1; then
        dnf5 repolist --enabled 2>/dev/null > "$stage/repos.txt" || true
    elif command -v dnf >/dev/null 2>&1; then
        dnf repolist 2>/dev/null > "$stage/repos.txt" || true
    elif [ -f /etc/pacman.conf ]; then
        cp -a /etc/pacman.conf "$stage/repos.txt" 2>/dev/null || true
    elif [ -d /etc/apt ]; then
        grep -rn '^deb' /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null > "$stage/repos.txt" || true
    fi

    {
        uname -a 2>/dev/null || true
        echo "--- /etc/os-release ---"
        cat /etc/os-release 2>/dev/null || true
        echo "--- /etc/fstab ---"
        cat /etc/fstab 2>/dev/null || true
        echo "--- findmnt -t btrfs ---"
        findmnt -t btrfs 2>/dev/null || true
        echo "--- /boot ---"
        ls -la /boot 2>/dev/null || true
    } > "$stage/system-info.txt"

    if [ -d "$home_dir/.config/paithosh" ]; then
        cp -a "$home_dir/.config/paithosh" "$stage/paithosh-config" 2>/dev/null || true
    fi

    local etc_backed_up="[]" etc_skipped="[]"
    local etc_candidates=(
        /etc/fstab /etc/crypttab /etc/os-release /etc/hostname /etc/hosts
        /etc/locale.conf /etc/vconsole.conf /etc/dnf /etc/yum.repos.d
        /etc/pacman.conf /etc/pacman.d /etc/systemd/system /etc/NetworkManager/system-connections
    )
    for ep in "${etc_candidates[@]}"; do
        if [ -e "$ep" ]; then
            if cp -a --parents "$ep" "$etc_stage" 2>/dev/null; then
                etc_backed_up=$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); a.append(sys.argv[2]); print(json.dumps(a))' "$etc_backed_up" "$ep")
            else
                etc_skipped=$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); a.append(sys.argv[2]); print(json.dumps(a))' "$etc_skipped" "$ep (permission denied)")
            fi
        fi
    done

    if [ -d "$etc_stage/etc" ]; then
        tar -czf "$stage/etc-snapshot.tar.gz" -C "$etc_stage" etc || fail_json "Failed to archive /etc snapshot"
    fi
    rm -rf "$etc_stage"

    local arc_tmp="$sys_dir/$id.tar.gz.tmp"
    local arc_final="$sys_dir/$id.tar.gz"
    tar -czf "$arc_tmp" -C "$stage" . || { rm -rf "$stage" "$arc_tmp"; fail_json "Failed to create system archive $arc_final"; }
    rm -rf "$stage"

    local arc_sha arc_bytes
    arc_sha=$(sha256sum "$arc_tmp" | awk '{print $1}')
    arc_bytes=$(stat -c '%s' "$arc_tmp")
    mv -f "$arc_tmp" "$arc_final"

    local etc_ok_cnt etc_skip_cnt
    etc_ok_cnt=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$etc_backed_up")
    etc_skip_cnt=$(python3 -c 'import json,sys; print(len(json.loads(sys.argv[1])))' "$etc_skipped")
    add_step_json "sys_archive" "ok" "Saved state archive (${etc_ok_cnt} /etc paths, ${etc_skip_cnt} skipped, sha256 ${arc_sha:0:12}...)"

    local now_iso meta_path
    now_iso=$(date -Iseconds)
    meta_path="$sys_dir/$id.meta.json"
    python3 -c '
import json, os, sys, tempfile
meta_path = sys.argv[1]
payload = {
    "id": sys.argv[2],
    "date": sys.argv[3],
    "reason": sys.argv[4],
    "trigger": sys.argv[5],
    "btrfs": {
        "created": sys.argv[6] == "1",
        "verified": sys.argv[7] == "1",
        "uuid": sys.argv[8],
        "parent_uuid": sys.argv[9],
        "subvol_id": int(sys.argv[10] or 0),
        "read_only": sys.argv[11] == "1",
        "subvol_path": sys.argv[12] if sys.argv[6] == "1" else "",
        "root_subvol": sys.argv[13],
        "root_uuid": sys.argv[14],
    },
    "boot": {
        "kernel": sys.argv[15],
        "boot_separate": sys.argv[16] == "1",
        "boot_fstype": sys.argv[17],
        "vmlinuz_exists": sys.argv[18] == "1",
    },
    "archive": {
        "name": os.path.basename(sys.argv[19]),
        "path": sys.argv[19],
        "sha256": sys.argv[20],
        "size_bytes": int(sys.argv[21] or 0),
        "etc_backed_up": json.loads(sys.argv[22]),
        "etc_skipped": json.loads(sys.argv[23]),
    },
    "steps": json.loads(sys.argv[24]),
}
d = os.path.dirname(meta_path)
fd, tp = tempfile.mkstemp(dir=d)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(payload, f, indent=2, ensure_ascii=False)
os.chmod(tp, 0o644)
os.replace(tp, meta_path)
' "$meta_path" "$id" "$now_iso" "$reason" "$trigger" "$btrfs_created" "$btrfs_verified" "$btrfs_uuid" "$btrfs_parent_uuid" "$btrfs_subvol_id" "$btrfs_ro" "$snap_rel" "$ROOT_SUBVOL" "$ROOT_UUID" "$KERNEL_RUNNING" "$BOOT_SEPARATE" "$BOOT_FSTYPE" "$VMLINUZ_EXISTS" "$arc_final" "$arc_sha" "$arc_bytes" "$etc_backed_up" "$etc_skipped" "$steps_json"

    if [ "$(id -u)" -eq 0 ] && [ -d "$home_dir" ]; then
        local owner_ug
        owner_ug=$(stat -c '%u:%g' "$home_dir" 2>/dev/null || true)
        if [ -n "$owner_ug" ]; then
            chown "$owner_ug" "$sys_dir" "$arc_final" "$meta_path" 2>/dev/null || true
        fi
    fi

    if [ "$(id -u)" -eq 0 ] && [ "$btrfs_created" = "1" ]; then
        mkdir -p "$REGISTRY_DIR"
        python3 -c '
import json, os, sys, tempfile, time
reg_file, meta_path = sys.argv[1], sys.argv[2]
with open(meta_path, "r", encoding="utf-8") as f:
    meta = json.load(f)
reg = {"snapshots": {}, "staged_rollback": None}
if os.path.isfile(reg_file):
    try:
        with open(reg_file, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                reg["snapshots"] = loaded.get("snapshots") if isinstance(loaded.get("snapshots"), dict) else {}
                reg["staged_rollback"] = loaded.get("staged_rollback")
    except Exception:
        pass
sid = meta["id"]
reg["snapshots"][sid] = {
    "id": sid,
    "created_at": meta["date"],
    "mtime": time.time(),
    "reason": meta["reason"],
    "trigger": meta["trigger"],
    "kernel": meta["boot"]["kernel"],
    "btrfs": meta["btrfs"],
    "archive": {
        "name": meta["archive"]["name"],
        "path": meta["archive"]["path"],
        "sha256": meta["archive"]["sha256"],
        "size_bytes": meta["archive"]["size_bytes"],
    },
    "etc_backed_up_count": len(meta["archive"]["etc_backed_up"]),
    "etc_skipped_count": len(meta["archive"]["etc_skipped"]),
    "steps": meta["steps"],
    "is_pre_rollback": False,
}
d = os.path.dirname(reg_file)
fd, tp = tempfile.mkstemp(dir=d)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
os.chmod(tp, 0o644)
os.replace(tp, reg_file)
' "$REGISTRY_FILE" "$meta_path"
    fi

    if [ "$emit_result" = "1" ]; then
        local final_json
        final_json=$(python3 -c '
import json, sys
with open(sys.argv[1], "r", encoding="utf-8") as f:
    meta = json.load(f)
print(json.dumps({"ok": True, "id": meta["id"], "btrfsCreated": meta["btrfs"]["created"], "btrfsVerified": meta["btrfs"]["verified"], "btrfsUuid": meta["btrfs"]["uuid"], "archivePath": meta["archive"]["path"], "archiveSha256": meta["archive"]["sha256"], "steps": meta["steps"]}, ensure_ascii=False))
' "$meta_path")
        result_json "$final_json"
    fi
}

cmd_pre_update() {
    local id="" reason="Pre-update snapshot" sys_dir="" home_dir="" with_btrfs="1" tool="" all="1" beta="0" ignore_pkgs=""
    local -a pkgs=()
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            --reason) reason="$2"; shift 2 ;;
            --sys-dir) sys_dir="$2"; shift 2 ;;
            --home-dir) home_dir="$2"; shift 2 ;;
            --with-btrfs) with_btrfs="$2"; shift 2 ;;
            --tool) tool="$2"; shift 2 ;;
            --all) all="$2"; shift 2 ;;
            --beta) beta="$2"; shift 2 ;;
            --ignore) ignore_pkgs="$2"; shift 2 ;;
            --) shift; pkgs=("$@"); break ;;
            *) fail_json "Unknown pre-update arg: $1" ;;
        esac
    done
    require_root
    [ -n "$tool" ] || fail_json "Missing --tool"
    if [ "$all" != "1" ] && [ ${#pkgs[@]} -eq 0 ] && [ "$tool" != "pacman" ]; then
        fail_json "No packages specified for upgrade"
    fi

    if ! cmd_create --id "$id" --reason "$reason" --trigger pre-update --sys-dir "$sys_dir" --home-dir "$home_dir" --with-btrfs "$with_btrfs" --no-result; then
        fail_json "Pre-update snapshot failed; package upgrade aborted for system safety"
    fi

    step "pkg_upgrade" "info" "Running $tool package upgrade..."
    local rc=0
    if [ "$tool" = "dnf5" ] || [ "$tool" = "dnf" ]; then
        local -a flags=("--refresh")
        [ "$beta" = "1" ] && flags+=("--enablerepo=updates-testing")
        if [ "$all" = "1" ]; then
            "$tool" upgrade -y "${flags[@]}" || rc=$?
        else
            "$tool" upgrade -y "${flags[@]}" -- "${pkgs[@]}" || rc=$?
        fi
    elif [ "$tool" = "pacman" ]; then
        if [ -n "$ignore_pkgs" ]; then
            pacman -Syu --noconfirm --ignore "$ignore_pkgs" || rc=$?
        else
            pacman -Syu --noconfirm || rc=$?
        fi
    elif [ "$tool" = "apt" ]; then
        DEBIAN_FRONTEND=noninteractive apt-get update || rc=$?
        if [ "$rc" -eq 0 ]; then
            if [ "$all" = "1" ]; then
                DEBIAN_FRONTEND=noninteractive apt-get upgrade -y || rc=$?
            else
                DEBIAN_FRONTEND=noninteractive apt-get install -y --only-upgrade -- "${pkgs[@]}" || rc=$?
            fi
        fi
    else
        fail_json "Unsupported package tool: $tool"
    fi

    if [ "$rc" -ne 0 ]; then
        step "pkg_upgrade" "fail" "$tool upgrade failed (exit $rc)"
        result_json "{\"ok\":false,\"id\":\"$id\",\"error\":\"Package upgrade failed (exit $rc). Snapshot $id is preserved for rollback.\"}"
        exit "$rc"
    fi

    step "pkg_upgrade" "ok" "Packages upgraded cleanly"
    result_json "{\"ok\":true,\"id\":\"$id\"}"
}

_run_verify_internal() {
    local id="$1" sys_dir="$2"
    validate_id "$id"
    detect_btrfs_env
    mount_top_level

    local snap_path="$TOP_MNT/$SNAP_SUBDIR/$id"
    local checks="[]"
    local can_rb=1
    local btrfs_uuid="" subvol_id=0 read_only=0 snap_kernels_json="" matched_kernels="[]" preferred_kernel=""
    local archive_sha_ok="null"

    add_chk() {
        checks=$(python3 -c 'import json,sys; a=json.loads(sys.argv[1]); a.append({"name":sys.argv[2],"status":sys.argv[3],"detail":sys.argv[4]}); print(json.dumps(a,ensure_ascii=False))' "$checks" "$1" "$2" "$3")
    }

    if [ ! -d "$snap_path" ]; then
        add_chk "Snapshot subvolume" "fail" "Not found at $SNAP_SUBDIR/$id"
        can_rb=0
    else
        local show_json
        if show_json=$(parse_btrfs_show "$snap_path"); then
            btrfs_uuid=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["uuid"])' "$show_json")
            subvol_id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["subvolId"])' "$show_json")
            read_only=$(python3 -c 'import json,sys; print("1" if json.loads(sys.argv[1])["readOnly"] else "0")' "$show_json")
            add_chk "Btrfs subvolume" "ok" "UUID ${btrfs_uuid:0:8}... (ID $subvol_id)"
        else
            add_chk "Btrfs subvolume" "fail" "Not a valid Btrfs subvolume"
            can_rb=0
        fi

        local reg_uuid="" rec_kernel=""
        if [ -f "$REGISTRY_FILE" ]; then
            reg_uuid=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print((d.get("snapshots",{}).get(sys.argv[2],{}).get("btrfs",{}) or {}).get("uuid",""))' "$REGISTRY_FILE" "$id" 2>/dev/null || true)
            rec_kernel=$(python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get("snapshots",{}).get(sys.argv[2],{}).get("kernel",""))' "$REGISTRY_FILE" "$id" 2>/dev/null || true)
        fi
        if [ -n "$reg_uuid" ]; then
            if [ "$reg_uuid" = "$btrfs_uuid" ]; then
                add_chk "Registry UUID match" "ok" "Matches /var/lib/paithosh/snapshots.json"
            else
                add_chk "Registry UUID match" "fail" "Mismatch: live $btrfs_uuid vs registry $reg_uuid"
                can_rb=0
            fi
        fi

        if [ "$read_only" = "1" ]; then
            add_chk "Read-only flag" "ok" "Snapshot is immutable (readonly)"
        else
            add_chk "Read-only flag" "warn" "Subvolume is writable (e.g. pre-rollback backup)"
        fi

        if [ -f "$snap_path/etc/fstab" ] && { [ -f "$snap_path/usr/lib/os-release" ] || [ -f "$snap_path/etc/os-release" ]; }; then
            add_chk "Root filesystem markers" "ok" "/etc/fstab and os-release present"
        else
            add_chk "Root filesystem markers" "fail" "Missing /etc/fstab or os-release inside snapshot"
            can_rb=0
        fi

        snap_kernels_json=$(find_matched_kernels "$snap_path" "$rec_kernel")
        matched_kernels=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1])["matchedKernels"]))' "$snap_kernels_json")
        preferred_kernel=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["preferredKernel"])' "$snap_kernels_json")
        if [ -n "$preferred_kernel" ]; then
            add_chk "/boot kernel compatibility" "ok" "Kernel $preferred_kernel present in both snapshot & /boot"
        else
            add_chk "/boot kernel compatibility" "fail" "No snapshot kernel exists in /boot/vmlinuz-* — rollback blocked to prevent unbootable system"
            can_rb=0
        fi
    fi

    if [ "$HOME_SEPARATE" -eq 1 ]; then
        add_chk "/home preservation" "ok" "/home is separate subvolume — user files untouched by rollback"
    else
        add_chk "/home preservation" "warn" "/home is not a separate mount"
    fi

    if [ -n "$sys_dir" ] && [ -f "$sys_dir/$id.tar.gz" ] && [ -f "$sys_dir/$id.meta.json" ]; then
        local exp_sha got_sha
        exp_sha=$(python3 -c 'import json,sys; print((json.load(open(sys.argv[1])).get("archive") or {}).get("sha256",""))' "$sys_dir/$id.meta.json" 2>/dev/null || true)
        got_sha=$(sha256sum "$sys_dir/$id.tar.gz" | awk '{print $1}')
        if [ -n "$exp_sha" ]; then
            if [ "$exp_sha" = "$got_sha" ]; then
                archive_sha_ok="true"
                add_chk "State archive SHA-256" "ok" "Verified (${got_sha:0:12}...)"
            else
                archive_sha_ok="false"
                add_chk "State archive SHA-256" "warn" "Archive checksum mismatch"
            fi
        fi
    fi

    VERIFY_CAN_RB="$can_rb"
    VERIFY_PREFERRED_KERNEL="$preferred_kernel"
    VERIFY_JSON=$(python3 -c '
import json, sys
print(json.dumps({
    "ok": sys.argv[1] == "1",
    "canRollback": sys.argv[1] == "1",
    "id": sys.argv[2],
    "btrfsUuid": sys.argv[3],
    "subvolId": int(sys.argv[4] or 0),
    "readOnly": sys.argv[5] == "1",
    "matchedKernels": json.loads(sys.argv[6]),
    "preferredKernel": sys.argv[7],
    "bootKernelOk": sys.argv[7] != "",
    "archiveShaOk": None if sys.argv[8] == "null" else (sys.argv[8] == "true"),
    "homeSeparate": sys.argv[9] == "1",
    "checks": json.loads(sys.argv[10]),
}, ensure_ascii=False))
' "$can_rb" "$id" "$btrfs_uuid" "$subvol_id" "$read_only" "$matched_kernels" "$preferred_kernel" "$archive_sha_ok" "$HOME_SEPARATE" "$checks")
}

cmd_verify() {
    local id="" sys_dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            --sys-dir) sys_dir="$2"; shift 2 ;;
            *) fail_json "Unknown verify arg: $1" ;;
        esac
    done
    [ -n "$id" ] || fail_json "Missing --id"
    require_root
    _run_verify_internal "$id" "$sys_dir"
    result_json "$VERIFY_JSON"
    [ "$VERIFY_CAN_RB" -eq 1 ]
}

cmd_rollback() {
    local id="" sys_dir=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            --sys-dir) sys_dir="$2"; shift 2 ;;
            *) fail_json "Unknown rollback arg: $1" ;;
        esac
    done
    [ -n "$id" ] || fail_json "Missing --id"
    require_root
    validate_id "$id"
    detect_btrfs_env

    if [ -f "$REGISTRY_FILE" ]; then
        local active_staged
        active_staged=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sr = d.get("staged_rollback")
if isinstance(sr, dict) and (not sr.get("boot_id") or sr.get("boot_id") == sys.argv[2]):
    print(sr.get("target_id",""))
' "$REGISTRY_FILE" "$BOOT_ID" 2>/dev/null || true)
        if [ -n "$active_staged" ]; then
            fail_json "A rollback to $active_staged is already staged for next boot. Reboot or undo it first."
        fi
    fi

    _run_verify_internal "$id" "$sys_dir"
    if [ "$VERIFY_CAN_RB" -ne 1 ]; then
        result_json "$VERIFY_JSON"
        exit 1
    fi
    # _run_verify_internal already mounted TOP_MNT under flock
    local snap_path="$TOP_MNT/$SNAP_SUBDIR/$id"
    local staging_path="$TOP_MNT/@paithosh-staging-$id"
    if [ -e "$staging_path" ]; then
        btrfs subvolume delete "$staging_path" >/dev/null 2>&1 || fail_json "Stale staging subvolume exists at @paithosh-staging-$id"
    fi

    step "rollback_clone" "info" "Creating writable root clone from $SNAP_SUBDIR/$id..."
    btrfs subvolume snapshot "$snap_path" "$staging_path" >/dev/null || fail_json "Failed to clone snapshot for rollback"
    [ -f "$staging_path/etc/fstab" ] || { btrfs subvolume delete "$staging_path" >/dev/null 2>&1 || true; fail_json "Cloned root failed /etc/fstab check"; }

    local stamp prev_name prev_rel
    stamp=$(date "+%Y-%m-%d_%H-%M-%S")
    prev_name="pre-rollback-$stamp"
    [ -e "$TOP_MNT/$SNAP_SUBDIR/$prev_name" ] && prev_name="pre-rollback-${stamp}-$$"
    prev_rel="$SNAP_SUBDIR/$prev_name"

    step "rollback_swap" "info" "Swapping subvol=$ROOT_SUBVOL (keeping previous root at $prev_rel)..."
    if ! mv "$TOP_MNT/$ROOT_SUBVOL" "$TOP_MNT/$prev_rel"; then
        btrfs subvolume delete "$staging_path" >/dev/null 2>&1 || true
        fail_json "Failed to move active subvol=$ROOT_SUBVOL aside"
    fi
    if ! mv "$staging_path" "$TOP_MNT/$ROOT_SUBVOL"; then
        mv "$TOP_MNT/$prev_rel" "$TOP_MNT/$ROOT_SUBVOL" || true
        fail_json "Failed to activate staged root; restored original subvolume"
    fi

    local prev_default_kernel=""
    if command -v grubby >/dev/null 2>&1 && [ -n "$VERIFY_PREFERRED_KERNEL" ] && [ -f "/boot/vmlinuz-$VERIFY_PREFERRED_KERNEL" ]; then
        prev_default_kernel=$(grubby --default-kernel 2>/dev/null || true)
        if [ "$prev_default_kernel" != "/boot/vmlinuz-$VERIFY_PREFERRED_KERNEL" ]; then
            if grubby --set-default "/boot/vmlinuz-$VERIFY_PREFERRED_KERNEL" >/dev/null 2>&1; then
                step "boot_kernel" "ok" "Set /boot default kernel to $VERIFY_PREFERRED_KERNEL"
            else
                step "boot_kernel" "warn" "Could not update default kernel via grubby; verify GRUB selection on boot"
            fi
        else
            step "boot_kernel" "ok" "Default /boot kernel already matches $VERIFY_PREFERRED_KERNEL"
        fi
    fi

    local prev_show_json prev_uuid="" prev_subvol_id=0
    if prev_show_json=$(parse_btrfs_show "$TOP_MNT/$prev_rel" 2>/dev/null); then
        prev_uuid=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["uuid"])' "$prev_show_json")
        prev_subvol_id=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1])["subvolId"])' "$prev_show_json")
    fi

    mkdir -p "$REGISTRY_DIR"
    local out_json
    out_json=$(python3 -c '
import datetime, json, os, sys, tempfile, time
reg_file, target_id, prev_name, prev_rel, pref_k, prev_def_k, boot_id, root_subvol, prev_uuid, prev_sid, cur_k = sys.argv[1:12]
reg = {"snapshots": {}, "staged_rollback": None}
if os.path.isfile(reg_file):
    try:
        with open(reg_file, "r", encoding="utf-8") as f:
            loaded = json.load(f)
            if isinstance(loaded, dict):
                reg["snapshots"] = loaded.get("snapshots") if isinstance(loaded.get("snapshots"), dict) else {}
    except Exception:
        pass
now_iso = datetime.datetime.now().astimezone().isoformat(timespec="seconds")
reg["snapshots"][prev_name] = {
    "id": prev_name,
    "created_at": now_iso,
    "mtime": time.time(),
    "reason": f"Previous root preserved before rollback to {target_id}",
    "trigger": "pre-rollback",
    "kernel": cur_k,
    "btrfs": {
        "created": True,
        "verified": True,
        "uuid": prev_uuid,
        "parent_uuid": "",
        "subvol_id": int(prev_sid or 0),
        "read_only": False,
        "subvol_path": prev_rel,
        "root_subvol": root_subvol,
        "root_uuid": "",
    },
    "archive": {"name": prev_name, "path": "", "sha256": "", "size_bytes": 0},
    "etc_backed_up_count": 0,
    "etc_skipped_count": 0,
    "steps": [],
    "is_pre_rollback": True,
}
staged = {
    "target_id": target_id,
    "prev_name": prev_name,
    "prev_subvol": prev_rel,
    "staged_at": now_iso,
    "preferred_kernel": pref_k,
    "prev_default_kernel": prev_def_k,
    "boot_id": boot_id,
    "root_subvol": root_subvol,
}
reg["staged_rollback"] = staged
d = os.path.dirname(reg_file)
fd, tp = tempfile.mkstemp(dir=d)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
os.chmod(tp, 0o644)
os.replace(tp, reg_file)
print(json.dumps({"ok": True, "stagedRollback": staged}, ensure_ascii=False))
' "$REGISTRY_FILE" "$id" "$prev_name" "$prev_rel" "$VERIFY_PREFERRED_KERNEL" "$prev_default_kernel" "$BOOT_ID" "$ROOT_SUBVOL" "$prev_uuid" "$prev_subvol_id" "$KERNEL_RUNNING")

    step "rollback_staged" "ok" "Rollback staged to $id. /home untouched. Reboot to activate."
    result_json "$out_json"
}

cmd_undo_rollback() {
    require_root
    detect_btrfs_env
    [ -f "$REGISTRY_FILE" ] || fail_json "No staged rollback record found"

    local sr_info
    sr_info=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sr = d.get("staged_rollback")
if not isinstance(sr, dict):
    sys.exit(1)
if sr.get("boot_id") and sr.get("boot_id") != sys.argv[2]:
    sys.exit(2)
print(json.dumps(sr))
' "$REGISTRY_FILE" "$BOOT_ID") || {
        local rc=$?
        [ "$rc" -eq 2 ] && fail_json "System has already rebooted since rollback was staged; undo is only available before reboot"
        fail_json "No active staged rollback found"
    }

    local prev_subvol prev_name prev_def_k
    prev_subvol=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("prev_subvol",""))' "$sr_info")
    prev_name=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("prev_name",""))' "$sr_info")
    prev_def_k=$(python3 -c 'import json,sys; print(json.loads(sys.argv[1]).get("prev_default_kernel",""))' "$sr_info")

    mount_top_level
    [ -d "$TOP_MNT/$prev_subvol" ] || fail_json "Previous root subvolume $prev_subvol is missing"

    local tmp_undo="@paithosh-undo-$(date +%s)-$$"
    mv "$TOP_MNT/$ROOT_SUBVOL" "$TOP_MNT/$tmp_undo" || fail_json "Failed to move staged root aside"
    if ! mv "$TOP_MNT/$prev_subvol" "$TOP_MNT/$ROOT_SUBVOL"; then
        mv "$TOP_MNT/$tmp_undo" "$TOP_MNT/$ROOT_SUBVOL" || true
        fail_json "Failed to restore previous root subvolume"
    fi
    btrfs subvolume delete "$TOP_MNT/$tmp_undo" >/dev/null 2>&1 || true

    if [ -n "$prev_def_k" ] && [ -f "$prev_def_k" ] && command -v grubby >/dev/null 2>&1; then
        grubby --set-default "$prev_def_k" >/dev/null 2>&1 || true
    fi

    python3 -c '
import json, os, sys, tempfile
reg_file, prev_name = sys.argv[1], sys.argv[2]
with open(reg_file, "r", encoding="utf-8") as f:
    reg = json.load(f)
reg["staged_rollback"] = None
if prev_name and isinstance(reg.get("snapshots"), dict):
    reg["snapshots"].pop(prev_name, None)
d = os.path.dirname(reg_file)
fd, tp = tempfile.mkstemp(dir=d)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
os.chmod(tp, 0o644)
os.replace(tp, reg_file)
' "$REGISTRY_FILE" "$prev_name"

    step "undo_rollback" "ok" "Staged rollback undone; original root restored"
    result_json '{"ok":true}'
}

cmd_delete() {
    local id="" sys_dir="" has_btrfs="0"
    while [ $# -gt 0 ]; do
        case "$1" in
            --id) id="$2"; shift 2 ;;
            --sys-dir) sys_dir="$2"; shift 2 ;;
            --has-btrfs) has_btrfs="$2"; shift 2 ;;
            *) fail_json "Unknown delete arg: $1" ;;
        esac
    done
    [ -n "$id" ] || fail_json "Missing --id"
    validate_id "$id"
    detect_btrfs_env

    if [ -f "$REGISTRY_FILE" ]; then
        local blocked
        blocked=$(python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sr = d.get("staged_rollback")
if isinstance(sr, dict) and (not sr.get("boot_id") or sr.get("boot_id") == sys.argv[3]):
    if sr.get("target_id") == sys.argv[2] or sr.get("prev_name") == sys.argv[2]:
        print("1")
if sys.argv[2] in (d.get("snapshots") or {}):
    print("REG_HAS")
' "$REGISTRY_FILE" "$id" "$BOOT_ID" 2>/dev/null || true)
        if [[ "$blocked" == *"1"* ]]; then
            fail_json "Cannot delete snapshot $id while it is part of a staged rollback"
        fi
        if [[ "$blocked" == *"REG_HAS"* ]]; then
            has_btrfs="1"
        fi
    fi

    if [ "$has_btrfs" = "1" ]; then
        require_root
        mount_top_level
        local snap_path="$TOP_MNT/$SNAP_SUBDIR/$id"
        if [ -d "$snap_path" ]; then
            if ! btrfs subvolume delete "$snap_path" >/dev/null 2>&1; then
                fail_json "Failed to delete Btrfs subvolume $SNAP_SUBDIR/$id; archive preserved"
            fi
            step "btrfs_delete" "ok" "Deleted Btrfs subvolume $SNAP_SUBDIR/$id"
        fi
        if [ -f "$REGISTRY_FILE" ]; then
            python3 -c '
import json, os, sys, tempfile
reg_file, sid = sys.argv[1], sys.argv[2]
with open(reg_file, "r", encoding="utf-8") as f:
    reg = json.load(f)
if isinstance(reg.get("snapshots"), dict):
    reg["snapshots"].pop(sid, None)
d = os.path.dirname(reg_file)
fd, tp = tempfile.mkstemp(dir=d)
with os.fdopen(fd, "w", encoding="utf-8") as f:
    json.dump(reg, f, indent=2, ensure_ascii=False)
os.chmod(tp, 0o644)
os.replace(tp, reg_file)
' "$REGISTRY_FILE" "$id"
        fi
        cleanup_top
    fi

    if [ -n "$sys_dir" ]; then
        rm -f "$sys_dir/$id.tar.gz" "$sys_dir/$id.meta.json"
    fi
    step "delete_done" "ok" "Deleted system backup $id"
    result_json "{\"ok\":true,\"id\":\"$id\"}"
}

[ $# -ge 1 ] || fail_json "Usage: paithosh-btrfs.sh <probe|create|pre-update|verify|rollback|undo-rollback|delete> ..."
SUBCMD="$1"
shift
case "$SUBCMD" in
    probe) cmd_probe "$@" ;;
    create) cmd_create "$@" ;;
    pre-update) cmd_pre_update "$@" ;;
    verify) cmd_verify "$@" ;;
    rollback) cmd_rollback "$@" ;;
    undo-rollback) cmd_undo_rollback "$@" ;;
    delete) cmd_delete "$@" ;;
    *) fail_json "Unknown subcommand: $SUBCMD" ;;
esac
