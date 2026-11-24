#!/usr/bin/env python3
"""Paithosh Storage Sight & Shredder backend (stdlib only)."""

from __future__ import annotations

import argparse
import json
import os
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import urllib.parse
from pathlib import Path

PROTECTED_DIR_NAMES = {
    ".git",
    ".hg",
    ".svn",
    ".ssh",
    ".gnupg",
    ".config",
    ".local",
    ".cache",
    ".pki",
    ".mozilla",
    ".thunderbird",
    "node_modules",
    "__pycache__",
    ".venv",
    "venv",
}

USER_CACHE_KEEP_PREFIXES = (
    "fontconfig",
    "mesa_shader_cache",
    "nvidia",
    "qtshadercache",
    "hyprland",
    "quickshell",
)


def emit_result(payload: dict) -> None:
    print("RESULT|" + json.dumps(payload, separators=(",", ":")), flush=True)


def dir_size(path: Path, seen_inodes: set[tuple[int, int]] | None = None, max_depth: int = 16) -> int:
    if not path.exists() or path.is_symlink():
        return 0
    total = 0
    stack: list[tuple[Path, int]] = [(path, 0)]
    while stack:
        cur, depth = stack.pop()
        if depth > max_depth:
            continue
        try:
            with os.scandir(cur) as it:
                for entry in it:
                    try:
                        if entry.is_symlink():
                            continue
                        st = entry.stat(follow_symlinks=False)
                        if stat.S_ISDIR(st.st_mode):
                            stack.append((Path(entry.path), depth + 1))
                        elif stat.S_ISREG(st.st_mode):
                            if seen_inodes is not None:
                                key = (st.st_dev, st.st_ino)
                                if key in seen_inodes:
                                    continue
                                seen_inodes.add(key)
                            total += st.st_size
                    except OSError:
                        continue
        except OSError:
            continue
    return total


def detect_mount_info(target: str = "/") -> tuple[str, str]:
    best_mp = "/"
    best_fs = "unknown"
    try:
        with open("/proc/mounts", "r", encoding="utf-8", errors="replace") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                mp, fs = parts[1], parts[2]
                if target.startswith(mp) and len(mp) >= len(best_mp):
                    best_mp = mp
                    best_fs = fs
    except OSError:
        pass
    return best_mp, best_fs


def is_protected_path(path: Path, home: Path, shell_dir: Path | None = None) -> bool:
    try:
        resolved = path.resolve(strict=False)
        home_res = home.resolve(strict=False)
    except OSError:
        return True

    if resolved == home_res or not str(resolved).startswith(str(home_res) + os.sep):
        return True

    if shell_dir is not None:
        try:
            shell_res = shell_dir.resolve(strict=False)
            if resolved == shell_res or str(resolved).startswith(str(shell_res) + os.sep):
                return True
        except OSError:
            pass

    rel_parts = resolved.relative_to(home_res).parts
    for part in rel_parts:
        if part in PROTECTED_DIR_NAMES or part.startswith("."):
            return True
    return False


def scan_stale_files(
    home: Path,
    stale_days: int,
    min_mb: int,
    shell_dir: Path | None = None,
    limit: int = 100,
    now_ts: float | None = None,
) -> list[dict]:
    now = now_ts if now_ts is not None else time.time()
    min_bytes = max(1, min_mb) * 1024 * 1024
    cutoff_sec = max(1, stale_days) * 86400
    shell_res = shell_dir.resolve(strict=False) if shell_dir is not None else None
    home_res = home.resolve(strict=False)

    candidates: list[dict] = []
    stack: list[Path] = [home_res]
    while stack:
        cur = stack.pop()
        try:
            with os.scandir(cur) as it:
                for entry in it:
                    try:
                        if entry.is_symlink():
                            continue
                        p = Path(entry.path)
                        name = entry.name
                        if name.startswith(".") or name in PROTECTED_DIR_NAMES:
                            continue
                        if shell_res is not None and p.resolve(strict=False) == shell_res:
                            continue
                        st = entry.stat(follow_symlinks=False)
                        if stat.S_ISDIR(st.st_mode):
                            stack.append(p)
                        elif stat.S_ISREG(st.st_mode):
                            if st.st_size < min_bytes:
                                continue
                            # Use max(mtime, atime) so recently accessed files aren't flagged on relatime mounts
                            last_touch = max(st.st_mtime, st.st_atime)
                            age_days = int((now - last_touch) // 86400)
                            if (now - last_touch) < cutoff_sec:
                                continue
                            ext = p.suffix.lower().lstrip(".")
                            rel = str(p.relative_to(home_res))
                            candidates.append(
                                {
                                    "name": name,
                                    "path": str(p),
                                    "relPath": "~/" + rel,
                                    "parentDir": str(p.parent),
                                    "sizeBytes": int(st.st_size),
                                    "ageDays": max(stale_days, age_days),
                                    "ext": ext,
                                    "mtime": int(st.st_mtime),
                                }
                            )
                    except OSError:
                        continue
        except OSError:
            continue

    candidates.sort(key=lambda item: item["sizeBytes"], reverse=True)
    return candidates[:limit]


def measure_package_cache_bytes() -> int:
    total = 0
    for cand in (
        Path("/var/cache/libdnf5"),
        Path("/var/cache/dnf"),
        Path("/var/cache/pacman/pkg"),
    ):
        if cand.exists():
            total += dir_size(cand)
    return total


def run_scan(stale_days: int, min_mb: int, shell_dir_str: str) -> dict:
    home = Path.home()
    shell_dir = Path(shell_dir_str) if shell_dir_str else None

    vfs = os.statvfs("/")
    total_bytes = int(vfs.f_blocks * vfs.f_frsize)
    free_bytes = int(vfs.f_bavail * vfs.f_frsize)
    used_bytes = max(0, total_bytes - int(vfs.f_bfree * vfs.f_frsize))
    mount_point, fs_type = detect_mount_info("/")

    # Apps: system/user app stores
    app_paths = [
        Path("/opt"),
        Path("/var/lib/flatpak"),
        Path("/var/lib/snapd"),
        home / ".local/share/flatpak",
        home / ".local/share/Steam",
        home / ".local/share/applications",
        home / "Applications",
    ]
    apps_bytes = sum(dir_size(p) for p in app_paths if p.exists())

    # User cache & Trash
    user_cache_dir = home / ".cache"
    trash_dir = home / ".local/share/Trash"
    user_cache_bytes = dir_size(user_cache_dir) + dir_size(trash_dir)

    # System cache (/var/tmp, /var/cache/dnf*|pacman, /var/log/journal)
    pkg_cache_bytes = measure_package_cache_bytes()
    var_tmp_bytes = dir_size(Path("/var/tmp"))
    journal_bytes = dir_size(Path("/var/log/journal"))
    system_cache_bytes = pkg_cache_bytes + var_tmp_bytes + journal_bytes
    tmp_cache_bytes = user_cache_bytes + system_cache_bytes

    # Paithosh shell size
    shell_bytes = dir_size(shell_dir) if (shell_dir and shell_dir.exists()) else 0

    # User documents (top-level non-hidden dirs & loose files in $HOME, excluding Applications)
    user_folders: list[dict] = []
    user_docs_bytes = 0
    try:
        with os.scandir(home) as it:
            for entry in it:
                try:
                    if entry.is_symlink():
                        continue
                    name = entry.name
                    if name.startswith(".") or name == "Applications":
                        continue
                    p = Path(entry.path)
                    st = entry.stat(follow_symlinks=False)
                    if stat.S_ISDIR(st.st_mode):
                        sz = dir_size(p)
                        user_docs_bytes += sz
                        if sz > 0:
                            user_folders.append(
                                {
                                    "name": name,
                                    "path": str(p),
                                    "bytes": sz,
                                }
                            )
                    elif stat.S_ISREG(st.st_mode):
                        user_docs_bytes += st.st_size
                except OSError:
                    continue
    except OSError:
        pass

    user_folders.sort(key=lambda d: d["bytes"], reverse=True)
    user_folders = user_folders[:6]

    # Clamp non-OS categories so they never exceed real used_bytes on shared Btrfs volumes
    accounted_non_os = apps_bytes + tmp_cache_bytes + user_docs_bytes
    if accounted_non_os > used_bytes and accounted_non_os > 0:
        scale = used_bytes / accounted_non_os
        apps_bytes = int(apps_bytes * scale)
        tmp_cache_bytes = int(tmp_cache_bytes * scale)
        user_docs_bytes = max(0, used_bytes - apps_bytes - tmp_cache_bytes)
    os_shell_bytes = max(0, used_bytes - apps_bytes - tmp_cache_bytes - user_docs_bytes)

    denom = max(1, total_bytes)
    categories = [
        {
            "key": "apps",
            "label": "Apps",
            "bytes": apps_bytes,
            "pct": round((apps_bytes / denom) * 100.0, 1),
            "detail": "Flatpak, /opt, Steam & local apps",
            "iconName": "grid",
        },
        {
            "key": "os",
            "label": "OS & Shell",
            "bytes": os_shell_bytes,
            "pct": round((os_shell_bytes / denom) * 100.0, 1),
            "detail": "System root, kernel & Paithosh shell",
            "iconName": "terminal",
        },
        {
            "key": "cache",
            "label": "Tmp & Cache",
            "bytes": tmp_cache_bytes,
            "pct": round((tmp_cache_bytes / denom) * 100.0, 1),
            "detail": "User cache, Trash, pkg cache & journal",
            "iconName": "archive",
        },
        {
            "key": "docs",
            "label": "User Documents",
            "bytes": user_docs_bytes,
            "pct": round((user_docs_bytes / denom) * 100.0, 1),
            "detail": "Home directories & personal files",
            "iconName": "folder",
        },
    ]

    stale_files = scan_stale_files(home, stale_days, min_mb, shell_dir=shell_dir)
    stale_total_bytes = sum(item["sizeBytes"] for item in stale_files)

    return {
        "ok": True,
        "mountPoint": mount_point,
        "fsType": fs_type,
        "totalBytes": total_bytes,
        "usedBytes": used_bytes,
        "freeBytes": free_bytes,
        "usedPct": round((used_bytes / denom) * 100.0, 1),
        "shellBytes": shell_bytes,
        "userCacheBytes": user_cache_bytes,
        "systemCacheBytes": system_cache_bytes,
        "categories": categories,
        "userFolders": user_folders,
        "staleFiles": stale_files,
        "staleTotalBytes": stale_total_bytes,
        "staleDays": stale_days,
        "minMb": min_mb,
    }


def clean_user_cache(home: Path) -> dict:
    freed = 0
    removed = 0
    errors: list[str] = []

    cache_dir = home / ".cache"
    if cache_dir.exists():
        try:
            with os.scandir(cache_dir) as it:
                for entry in it:
                    name = entry.name
                    if any(name.startswith(pref) for pref in USER_CACHE_KEEP_PREFIXES):
                        continue
                    p = Path(entry.path)
                    try:
                        if entry.is_symlink() or entry.is_file(follow_symlinks=False):
                            sz = entry.stat(follow_symlinks=False).st_size
                            p.unlink()
                            freed += sz
                            removed += 1
                        elif entry.is_dir(follow_symlinks=False):
                            sz = dir_size(p)
                            shutil.rmtree(p, ignore_errors=False)
                            freed += sz
                            removed += 1
                    except OSError as exc:
                        errors.append(f"{name}: {exc}")
        except OSError as exc:
            errors.append(str(exc))

    for sub in ("files", "info"):
        tdir = home / ".local/share/Trash" / sub
        if tdir.exists():
            try:
                with os.scandir(tdir) as it:
                    for entry in it:
                        p = Path(entry.path)
                        try:
                            if entry.is_dir(follow_symlinks=False) and not entry.is_symlink():
                                sz = dir_size(p)
                                shutil.rmtree(p)
                                freed += sz
                            else:
                                sz = entry.stat(follow_symlinks=False).st_size
                                p.unlink()
                                freed += sz
                            removed += 1
                        except OSError as exc:
                            errors.append(f"Trash/{sub}/{entry.name}: {exc}")
            except OSError as exc:
                errors.append(str(exc))

    return {
        "ok": True,
        "scope": "user",
        "freedBytes": freed,
        "removedCount": removed,
        "errors": errors[:10],
    }


def clean_system_cache() -> dict:
    if os.geteuid() != 0:
        return {"ok": False, "error": "Root privileges required for system cache cleanup"}

    before_bytes = measure_package_cache_bytes() + dir_size(Path("/var/tmp")) + dir_size(Path("/var/log/journal"))
    ran: list[str] = []
    errors: list[str] = []

    if shutil.which("dnf5"):
        res = subprocess.run(["dnf5", "clean", "all"], capture_output=True, text=True)
        ran.append("dnf5 clean all")
        if res.returncode != 0 and res.stderr.strip():
            errors.append(res.stderr.strip())
    elif shutil.which("dnf"):
        res = subprocess.run(["dnf", "clean", "all"], capture_output=True, text=True)
        ran.append("dnf clean all")
        if res.returncode != 0 and res.stderr.strip():
            errors.append(res.stderr.strip())
    elif shutil.which("pacman"):
        res = subprocess.run(["pacman", "-Sc", "--noconfirm"], capture_output=True, text=True)
        ran.append("pacman -Sc")
        if res.returncode != 0 and res.stderr.strip():
            errors.append(res.stderr.strip())

    if shutil.which("journalctl"):
        res = subprocess.run(["journalctl", "--vacuum-time=7d"], capture_output=True, text=True)
        ran.append("journalctl --vacuum-time=7d")
        if res.returncode != 0 and res.stderr.strip():
            errors.append(res.stderr.strip())

    # Remove stale regular files in /var/tmp older than 24h (never touch sockets/pipes)
    now = time.time()
    var_tmp = Path("/var/tmp")
    if var_tmp.exists():
        try:
            with os.scandir(var_tmp) as it:
                for entry in it:
                    try:
                        if entry.is_symlink():
                            continue
                        st = entry.stat(follow_symlinks=False)
                        if stat.S_ISREG(st.st_mode) and (now - st.st_mtime) > 86400:
                            os.unlink(entry.path)
                    except OSError:
                        continue
        except OSError:
            pass

    after_bytes = measure_package_cache_bytes() + dir_size(Path("/var/tmp")) + dir_size(Path("/var/log/journal"))
    freed = max(0, before_bytes - after_bytes)
    return {
        "ok": True,
        "scope": "system",
        "freedBytes": freed,
        "commands": ran,
        "errors": errors[:10],
    }


def move_to_trash(path: Path, home: Path) -> None:
    if shutil.which("gio"):
        res = subprocess.run(["gio", "trash", str(path)], capture_output=True, text=True)
        if res.returncode == 0:
            return

    trash_root = home / ".local/share/Trash"
    files_dir = trash_root / "files"
    info_dir = trash_root / "info"
    files_dir.mkdir(parents=True, exist_ok=True)
    info_dir.mkdir(parents=True, exist_ok=True)

    base = path.name
    dest_name = base
    counter = 1
    while (files_dir / dest_name).exists() or (info_dir / f"{dest_name}.trashinfo").exists():
        stem = path.stem
        suf = path.suffix
        dest_name = f"{stem}.{counter}{suf}"
        counter += 1

    ts = time.strftime("%Y-%m-%dT%H:%M:%S")
    quoted = urllib.parse.quote(str(path.resolve(strict=False)), safe="/")
    info_content = f"[Trash Info]\nPath={quoted}\nDeletionDate={ts}\n"
    (info_dir / f"{dest_name}.trashinfo").write_text(info_content, encoding="utf-8")
    shutil.move(str(path), str(files_dir / dest_name))


def shred_files(paths: list[str], mode: str, home: Path, shell_dir: Path | None = None) -> dict:
    freed = 0
    removed = 0
    skipped: list[str] = []

    for raw in paths:
        p = Path(raw)
        try:
            if p.is_symlink() or not p.exists():
                skipped.append(f"{raw} (missing or symlink)")
                continue
            st = p.stat(follow_symlinks=False)
            if not stat.S_ISREG(st.st_mode):
                skipped.append(f"{raw} (not a regular file)")
                continue
            if is_protected_path(p, home, shell_dir=shell_dir):
                skipped.append(f"{raw} (protected path)")
                continue
            sz = st.st_size
            if mode == "permanent":
                p.unlink()
            else:
                move_to_trash(p, home)
            freed += sz
            removed += 1
        except OSError as exc:
            skipped.append(f"{raw} ({exc})")

    return {
        "ok": True,
        "mode": mode,
        "freedBytes": freed,
        "removedCount": removed,
        "skipped": skipped[:10],
    }


def run_self_test() -> int:
    with tempfile.TemporaryDirectory() as tmp:
        fake_home = Path(tmp) / "home"
        docs = fake_home / "Documents"
        prot = fake_home / ".config"
        docs.mkdir(parents=True)
        prot.mkdir(parents=True)

        old_big = docs / "old_archive.bin"
        old_big.write_bytes(b"x" * (2 * 1024 * 1024))
        old_ts = time.time() - (45 * 86400)
        os.utime(old_big, (old_ts, old_ts))

        recent_big = docs / "recent_video.bin"
        recent_big.write_bytes(b"y" * (2 * 1024 * 1024))

        small_old = docs / "tiny.txt"
        small_old.write_bytes(b"z" * 128)
        os.utime(small_old, (old_ts, old_ts))

        hidden_old = prot / "secret.bin"
        hidden_old.write_bytes(b"s" * (2 * 1024 * 1024))
        os.utime(hidden_old, (old_ts, old_ts))

        sym = docs / "link.bin"
        sym.symlink_to(old_big)

        found = scan_stale_files(fake_home, stale_days=30, min_mb=1)
        assert len(found) == 1, f"Expected 1 stale file, got {found}"
        assert found[0]["name"] == "old_archive.bin"

        # Protected and symlink paths must be rejected
        res_prot = shred_files([str(hidden_old), str(sym)], "permanent", fake_home)
        assert res_prot["removedCount"] == 0, res_prot
        assert hidden_old.exists()

        # Trash mode moves file and writes .trashinfo
        res_trash = shred_files([str(old_big)], "trash", fake_home)
        assert res_trash["removedCount"] == 1, res_trash
        assert not old_big.exists()
        assert (fake_home / ".local/share/Trash/files/old_archive.bin").exists()
        assert (fake_home / ".local/share/Trash/info/old_archive.bin.trashinfo").exists()

        # Permanent mode unlinks file
        res_perm = shred_files([str(recent_big)], "permanent", fake_home)
        assert res_perm["removedCount"] == 1, res_perm
        assert not recent_big.exists()

    print("SELF-TEST PASSED")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Paithosh Storage Sight & Shredder")
    parser.add_argument("--self-test", action="store_true", help="Run built-in safety self-test")
    sub = parser.add_subparsers(dest="cmd")

    p_scan = sub.add_parser("scan")
    p_scan.add_argument("--stale-days", type=int, default=30)
    p_scan.add_argument("--min-mb", type=int, default=50)
    p_scan.add_argument("--shell-dir", default="")

    p_cache = sub.add_parser("clean-cache")
    p_cache.add_argument("--scope", choices=("user", "system"), required=True)

    p_shred = sub.add_parser("shred-files")
    p_shred.add_argument("--mode", choices=("trash", "permanent"), default="trash")
    p_shred.add_argument("--shell-dir", default="")

    args = parser.parse_args()
    if args.self_test:
        return run_self_test()

    if args.cmd == "scan":
        emit_result(run_scan(args.stale_days, args.min_mb, args.shell_dir))
        return 0
    if args.cmd == "clean-cache":
        if args.scope == "user":
            emit_result(clean_user_cache(Path.home()))
        else:
            emit_result(clean_system_cache())
        return 0
    if args.cmd == "shred-files":
        raw_stdin = sys.stdin.read().strip()
        try:
            paths = json.loads(raw_stdin) if raw_stdin else []
            if not isinstance(paths, list):
                paths = []
        except json.JSONDecodeError:
            emit_result({"ok": False, "error": "Invalid JSON file list"})
            return 1
        shell_dir = Path(args.shell_dir) if args.shell_dir else None
        emit_result(shred_files([str(x) for x in paths], args.mode, Path.home(), shell_dir=shell_dir))
        return 0

    parser.print_help()
    return 1


if __name__ == "__main__":
    sys.exit(main())
