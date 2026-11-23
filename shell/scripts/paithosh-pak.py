#!/usr/bin/env python3
"""Paithosh .pak user data backup, store, verification, and safe restore tool.

A .pak file is a standard ZIP archive (PKZIP / ZIP_DEFLATED) containing selected
/home user folders and an optional .paithosh-pak.json manifest at archive root.
"""

import argparse
import datetime
import hashlib
import json
import os
import posixpath
import shutil
import stat
import sys
import zipfile
from pathlib import PurePosixPath

MANIFEST_NAME = ".paithosh-pak.json"
EXCLUDE_DIRS = {
    "node_modules",
    ".cache",
    "target",
    "__pycache__",
    ".venv",
    "venv",
    "Cache",
    "Cache_Data",
    "Code Cache",
    "GPUCache",
    "DawnCache",
    "ShaderCache",
    "CachedData",
    "Trash",
}


def emit(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False, separators=(",", ":")))
    sys.exit(code)


def fail(msg, extra=None, code=1):
    payload = {"ok": False, "error": str(msg)}
    if extra:
        payload.update(extra)
    emit(payload, code=code)


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            chunk = f.read(1024 * 1024)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def is_safe_rel_folder(folder):
    if not folder or folder.startswith("/") or folder.startswith("\\") or "\x00" in folder:
        return False
    parts = PurePosixPath(folder.replace("\\", "/")).parts
    return len(parts) > 0 and ".." not in parts and "." not in parts


def check_zip_entry_safety(info, zf):
    name = info.filename
    if not name or name.startswith("/") or name.startswith("\\") or "\x00" in name:
        return False, f"unsafe path: {name}"
    norm = name.replace("\\", "/")
    parts = PurePosixPath(norm).parts
    if ".." in parts:
        return False, f"path traversal: {name}"
    if len(norm) >= 2 and norm[1] == ":" and norm[0].isalpha():
        return False, f"drive path: {name}"

    mode = (info.external_attr >> 16) & 0o170000
    if mode == stat.S_IFLNK:
        try:
            target = zf.read(info).decode("utf-8", errors="replace").strip("\x00")
        except Exception as exc:
            return False, f"unreadable symlink {name}: {exc}"
        if not target or target.startswith("/") or target.startswith("\\") or "\x00" in target:
            return False, f"unsafe symlink target in {name} -> {target}"
        parent_dir = posixpath.dirname(norm.rstrip("/"))
        resolved = posixpath.normpath(posixpath.join(parent_dir, target)) if parent_dir else posixpath.normpath(target)
        if resolved == ".." or resolved.startswith("../") or resolved.startswith("/"):
            return False, f"escaping symlink {name} -> {target}"
    return True, ""


def summarize_archive(zf):
    manifest = None
    has_manifest = False
    top_folders = []
    seen_top = set()
    entry_count = 0
    uncompressed = 0
    compressed = 0

    for info in zf.infolist():
        name = info.filename
        if name == MANIFEST_NAME:
            has_manifest = True
            try:
                raw = zf.read(info).decode("utf-8", errors="replace")
                parsed = json.loads(raw)
                if isinstance(parsed, dict):
                    manifest = parsed
            except Exception:
                manifest = None
            continue
        if name.endswith("/") and info.file_size == 0:
            top = name.rstrip("/").split("/", 1)[0]
            if top and top not in seen_top:
                seen_top.add(top)
                top_folders.append(top)
            continue
        entry_count += 1
        uncompressed += max(0, info.file_size)
        compressed += max(0, info.compress_size)
        top = name.split("/", 1)[0]
        if top and top not in seen_top:
            seen_top.add(top)
            top_folders.append(top)

    if manifest and isinstance(manifest.get("folders"), list) and manifest["folders"]:
        folders = [str(x) for x in manifest["folders"]]
    else:
        folders = top_folders

    return has_manifest, manifest, folders, entry_count, compressed, uncompressed


def validate_pak(file_path, run_crc=False, compute_sha=False):
    path = os.path.abspath(file_path)
    ext_is_pak = path.lower().endswith(".pak")
    result = {
        "ok": False,
        "valid": False,
        "path": path,
        "name": os.path.basename(path),
        "extIsPak": ext_is_pak,
        "isZip": False,
        "hasManifest": False,
        "manifest": None,
        "folders": [],
        "entryCount": 0,
        "sizeBytes": 0,
        "compressedBytes": 0,
        "uncompressedBytes": 0,
        "crcOk": None if not run_crc else False,
        "badMember": "",
        "sha256": "",
        "unsafePaths": [],
        "skippedCount": 0,
        "skippedSample": [],
        "error": "",
    }

    if not os.path.isfile(path):
        result["error"] = f"File not found: {path}"
        return result

    try:
        result["sizeBytes"] = os.path.getsize(path)
    except OSError as exc:
        result["error"] = f"Cannot stat file: {exc}"
        return result

    if not zipfile.is_zipfile(path):
        result["error"] = "Not a valid ZIP-based .pak archive"
        return result

    result["isZip"] = True
    unsafe_paths = []
    try:
        with zipfile.ZipFile(path, "r") as zf:
            for info in zf.infolist():
                safe, reason = check_zip_entry_safety(info, zf)
                if not safe:
                    unsafe_paths.append(reason)

            has_manifest, manifest, folders, entry_count, comp, uncomp = summarize_archive(zf)
            result["hasManifest"] = has_manifest
            result["manifest"] = manifest
            result["folders"] = folders
            result["entryCount"] = entry_count
            result["compressedBytes"] = comp
            result["uncompressedBytes"] = uncomp
            if manifest:
                result["skippedCount"] = int(manifest.get("skipped_count", 0) or 0)
                sample = manifest.get("skipped_sample", [])
                result["skippedSample"] = sample if isinstance(sample, list) else []

            if run_crc:
                bad = zf.testzip()
                result["crcOk"] = bad is None
                result["badMember"] = bad or ""
    except (zipfile.BadZipFile, OSError, RuntimeError) as exc:
        result["error"] = f"Archive read error: {exc}"
        return result

    result["unsafePaths"] = unsafe_paths

    if compute_sha:
        try:
            result["sha256"] = sha256_file(path)
        except OSError as exc:
            result["error"] = f"Checksum error: {exc}"
            return result

    if unsafe_paths:
        result["error"] = f"Blocked unsafe archive path(s): {unsafe_paths[0]}"
        return result
    if run_crc and not result["crcOk"]:
        result["error"] = f"CRC-32 verification failed at entry: {result['badMember']}"
        return result

    result["valid"] = True
    result["ok"] = True
    return result


def cmd_create(args):
    home_dir = os.path.abspath(args.home)
    store_dir = os.path.abspath(args.store_dir)
    exclude_cache = args.exclude_cache == "1"

    if not os.path.isdir(home_dir):
        fail(f"Home directory does not exist: {home_dir}")

    folders = []
    for f in args.folders:
        clean = f.strip().strip("/")
        if not is_safe_rel_folder(clean):
            fail(f"Invalid folder name: {f}")
        src = os.path.join(home_dir, clean)
        if not os.path.isdir(src):
            fail(f"Selected folder does not exist: {src}")
        if clean not in folders:
            folders.append(clean)

    if not folders:
        fail("No valid /home folders selected")

    try:
        os.makedirs(store_dir, exist_ok=True)
    except OSError as exc:
        fail(f"Cannot create store directory {store_dir}: {exc}")

    try:
        usage = shutil.disk_usage(store_dir)
        if usage.free < 32 * 1024 * 1024:
            fail(f"Low disk space in {store_dir} ({usage.free // (1024 * 1024)} MB free)")
    except OSError:
        pass

    stamp = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    out_name = f"paithosh-data-{stamp}.pak"
    out_path = os.path.join(store_dir, out_name)
    if os.path.exists(out_path):
        out_name = f"paithosh-data-{stamp}-{os.getpid()}.pak"
        out_path = os.path.join(store_dir, out_name)
    tmp_path = out_path + ".tmp"
    real_tmp = os.path.realpath(tmp_path)
    real_out = os.path.realpath(out_path)
    real_store = os.path.realpath(store_dir)

    file_count = 0
    uncompressed_bytes = 0
    skipped = []
    last_pct = -1

    # Quick pre-scan of file count for accurate progress %
    total_files_est = 0
    for folder in folders:
        src_root = os.path.join(home_dir, folder)
        for cur_root, dirs, files in os.walk(src_root, topdown=True, followlinks=False):
            if exclude_cache:
                dirs[:] = [d for d in dirs if d not in EXCLUDE_DIRS and not os.path.islink(os.path.join(cur_root, d))]
            else:
                dirs[:] = [d for d in dirs if not os.path.islink(os.path.join(cur_root, d))]
            total_files_est += len(files)
    total_files_est = max(1, total_files_est)

    def emit_progress(pct):
        nonlocal last_pct
        if pct > last_pct:
            last_pct = pct
            print(f"PROGRESS|{pct}", flush=True)

    emit_progress(0)

    def record_skip(rel, reason):
        skipped.append(f"{rel} ({reason})")

    try:
        with zipfile.ZipFile(tmp_path, "w", compression=zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
            for folder in folders:
                src_root = os.path.join(home_dir, folder)
                for cur_root, dirs, files in os.walk(src_root, topdown=True, followlinks=False):
                    # Skip the store directory itself if user placed it inside a backed-up folder
                    next_dirs = []
                    for d in dirs:
                        if exclude_cache and d in EXCLUDE_DIRS:
                            continue
                        dp = os.path.join(cur_root, d)
                        if os.path.realpath(dp) == real_store:
                            rel_d = os.path.relpath(dp, home_dir)
                            record_skip(rel_d, "backup store directory")
                            continue
                        if os.path.islink(dp):
                            rel_d = os.path.relpath(dp, home_dir).replace(os.sep, "/")
                            try:
                                target = os.readlink(dp)
                                zi = zipfile.ZipInfo(rel_d)
                                zi.external_attr = (stat.S_IFLNK | 0o777) << 16
                                zf.writestr(zi, target.encode("utf-8"))
                                file_count += 1
                            except OSError as exc:
                                record_skip(rel_d, f"symlink error: {exc.strerror or exc}")
                            continue
                        next_dirs.append(d)
                    dirs[:] = next_dirs

                    if not dirs and not files:
                        rel_dir = os.path.relpath(cur_root, home_dir).replace(os.sep, "/")
                        if rel_dir and rel_dir != ".":
                            zi = zipfile.ZipInfo(rel_dir.rstrip("/") + "/")
                            zf.writestr(zi, b"")

                    for fn in files:
                        fp = os.path.join(cur_root, fn)
                        rp = os.path.realpath(fp)
                        if rp in (real_tmp, real_out):
                            continue
                        rel = os.path.relpath(fp, home_dir).replace(os.sep, "/")
                        try:
                            st = os.lstat(fp)
                        except OSError as exc:
                            record_skip(rel, f"stat failed: {exc.strerror or exc}")
                            continue

                        if stat.S_ISLNK(st.st_mode):
                            try:
                                target = os.readlink(fp)
                                zi = zipfile.ZipInfo(rel)
                                zi.date_time = datetime.datetime.fromtimestamp(st.st_mtime).timetuple()[:6] if st.st_mtime >= 315532800 else (1980, 1, 1, 0, 0, 0)
                                zi.external_attr = (stat.S_IFLNK | 0o777) << 16
                                zf.writestr(zi, target.encode("utf-8"))
                                file_count += 1
                            except OSError as exc:
                                record_skip(rel, f"symlink error: {exc.strerror or exc}")
                            continue

                        if stat.S_ISSOCK(st.st_mode):
                            record_skip(rel, "socket")
                            continue
                        if stat.S_ISFIFO(st.st_mode):
                            record_skip(rel, "fifo")
                            continue
                        if stat.S_ISBLK(st.st_mode) or stat.S_ISCHR(st.st_mode):
                            record_skip(rel, "device")
                            continue
                        if not stat.S_ISREG(st.st_mode):
                            record_skip(rel, "special file")
                            continue

                        try:
                            zf.write(fp, arcname=rel)
                            file_count += 1
                            uncompressed_bytes += st.st_size
                            emit_progress(min(94, int((file_count * 94) / total_files_est)))
                        except OSError as exc:
                            record_skip(rel, f"unreadable: {exc.strerror or exc}")

            emit_progress(95)
            manifest = {
                "format": "paithosh-pak",
                "version": 1,
                "created_at": datetime.datetime.now().astimezone().isoformat(timespec="seconds"),
                "hostname": os.uname().nodename,
                "home_dir": home_dir,
                "folders": folders,
                "exclude_heavy_cache": exclude_cache,
                "file_count": file_count,
                "total_uncompressed_bytes": uncompressed_bytes,
                "skipped_count": len(skipped),
                "skipped_sample": skipped[:25],
            }
            zf.writestr(MANIFEST_NAME, json.dumps(manifest, indent=2, ensure_ascii=False).encode("utf-8"))

        # Verify CRC-32 before promoting .tmp -> .pak
        emit_progress(96)
        with zipfile.ZipFile(tmp_path, "r") as verify_zf:
            bad = verify_zf.testzip()
            if bad is not None:
                raise RuntimeError(f"CRC check failed after compression at {bad}")

        emit_progress(98)
        digest = sha256_file(tmp_path)
        size_bytes = os.path.getsize(tmp_path)
        os.replace(tmp_path, out_path)
        emit_progress(100)
    except Exception as exc:
        try:
            if os.path.exists(tmp_path):
                os.unlink(tmp_path)
        except OSError:
            pass
        fail(f"Failed to create .pak archive: {exc}")

    emit(
        {
            "ok": True,
            "path": out_path,
            "name": out_name,
            "sizeBytes": size_bytes,
            "sha256": digest,
            "fileCount": file_count,
            "uncompressedBytes": uncompressed_bytes,
            "folders": folders,
            "skippedCount": len(skipped),
            "skippedSample": skipped[:25],
            "crcOk": True,
        }
    )


def cmd_list(args):
    store_dir = os.path.abspath(args.store_dir)
    if not os.path.isdir(store_dir):
        emit({"ok": True, "storeDir": store_dir, "items": []})

    entries = []
    try:
        for entry in os.scandir(store_dir):
            if not entry.is_file():
                continue
            low = entry.name.lower()
            if not (low.endswith(".pak") or low.endswith(".zip")):
                continue
            st = entry.stat()
            entries.append((st.st_mtime, st.st_size, entry.name, entry.path, low.endswith(".zip")))
    except OSError as exc:
        fail(f"Cannot scan store directory {store_dir}: {exc}")

    entries.sort(key=lambda x: x[0], reverse=True)
    items = []
    for mtime, size_bytes, name, path, legacy_zip in entries:
        dt_str = datetime.datetime.fromtimestamp(mtime).strftime("%Y-%m-%d %H:%M")
        has_manifest = False
        corrupt = False
        folders = []
        file_count = 0
        uncomp = 0
        skipped_count = 0
        try:
            if not zipfile.is_zipfile(path):
                corrupt = True
            else:
                with zipfile.ZipFile(path, "r") as zf:
                    has_manifest, manifest, folders, file_count, _comp, uncomp = summarize_archive(zf)
                    if manifest:
                        skipped_count = int(manifest.get("skipped_count", 0) or 0)
                        if manifest.get("file_count") is not None:
                            file_count = int(manifest.get("file_count") or file_count)
                        if manifest.get("total_uncompressed_bytes") is not None:
                            uncomp = int(manifest.get("total_uncompressed_bytes") or uncomp)
        except Exception:
            corrupt = True

        items.append(
            {
                "id": name,
                "name": name,
                "path": path,
                "sizeBytes": size_bytes,
                "mtime": mtime,
                "dateText": dt_str,
                "legacyZip": legacy_zip,
                "hasManifest": has_manifest,
                "corrupt": corrupt,
                "folders": folders,
                "fileCount": file_count,
                "uncompressedBytes": uncomp,
                "skippedCount": skipped_count,
            }
        )

    emit({"ok": True, "storeDir": store_dir, "items": items})


def cmd_inspect(args):
    res = validate_pak(args.file, run_crc=False, compute_sha=False)
    emit(res, code=0 if res["ok"] else 1)


def cmd_verify(args):
    res = validate_pak(args.file, run_crc=True, compute_sha=True)
    emit(res, code=0 if res["ok"] else 1)


def cmd_import(args):
    src = os.path.abspath(args.file)
    store_dir = os.path.abspath(args.store_dir)
    if not src.lower().endswith(".pak") and not args.allow_zip:
        fail("Only .pak backup packages can be imported into the .pak store")

    res = validate_pak(src, run_crc=True, compute_sha=True)
    if not res["ok"]:
        emit(res, code=1)

    try:
        os.makedirs(store_dir, exist_ok=True)
    except OSError as exc:
        fail(f"Cannot create store directory: {exc}")

    base = os.path.basename(src)
    if base.lower().endswith(".zip"):
        base = base[:-4] + ".pak"
    dst = os.path.join(store_dir, base)

    if os.path.exists(dst) and os.path.realpath(dst) == os.path.realpath(src):
        emit(
            {
                "ok": True,
                "alreadyInStore": True,
                "path": dst,
                "name": base,
                "sha256": res["sha256"],
                "sizeBytes": res["sizeBytes"],
            }
        )

    if os.path.exists(dst):
        stem = base[:-4] if base.lower().endswith(".pak") else base
        suffix = datetime.datetime.now().strftime("%H%M%S")
        cand = os.path.join(store_dir, f"{stem}-{suffix}.pak")
        idx = 2
        while os.path.exists(cand):
            cand = os.path.join(store_dir, f"{stem}-{suffix}-{idx}.pak")
            idx += 1
        dst = cand

    tmp_dst = dst + ".tmp"
    try:
        shutil.copy2(src, tmp_dst)
        os.replace(tmp_dst, dst)
    except OSError as exc:
        try:
            if os.path.exists(tmp_dst):
                os.unlink(tmp_dst)
        except OSError:
            pass
        fail(f"Failed to import .pak into store: {exc}")

    emit(
        {
            "ok": True,
            "alreadyInStore": False,
            "path": dst,
            "name": os.path.basename(dst),
            "sha256": res["sha256"],
            "sizeBytes": os.path.getsize(dst),
        }
    )


def ensure_safe_extract_path(target_root_real, rel_name):
    norm = rel_name.replace("\\", "/").lstrip("/")
    parts = [p for p in norm.split("/") if p and p != "."]
    if not parts or ".." in parts:
        raise ValueError(f"Unsafe archive entry path: {rel_name}")
    cur = target_root_real
    for part in parts[:-1]:
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            raise ValueError(f"Refusing to traverse symlink component during restore: {cur}")
    final_path = os.path.join(cur, parts[-1])
    if os.path.realpath(os.path.dirname(final_path)) != target_root_real and not os.path.realpath(os.path.dirname(final_path)).startswith(target_root_real + os.sep):
        raise ValueError(f"Path escape detected: {final_path}")
    return final_path


def cmd_restore(args):
    pak_path = os.path.abspath(args.file)
    mode = args.mode
    home_dir = os.path.abspath(args.home)

    check = validate_pak(pak_path, run_crc=True, compute_sha=False)
    if not check["ok"]:
        emit(check, code=1)

    base_name = os.path.basename(pak_path)
    if base_name.lower().endswith(".pak"):
        stem = base_name[:-4]
    elif base_name.lower().endswith(".zip"):
        stem = base_name[:-4]
    else:
        stem = base_name
    stem = stem or "restored"

    if mode == "staged":
        base_dest = os.path.abspath(args.dest) if args.dest else os.path.join(home_dir, "Backups", "restored")
        os.makedirs(base_dest, exist_ok=True)
        target_root = os.path.join(base_dest, stem)
        if os.path.lexists(target_root):
            if os.path.isdir(target_root):
                has_contents = bool(os.listdir(target_root))
            else:
                has_contents = True
            if has_contents:
                stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
                cand = os.path.join(base_dest, f"{stem}-{stamp}")
                idx = 2
                while os.path.lexists(cand):
                    cand = os.path.join(base_dest, f"{stem}-{stamp}-{idx}")
                    idx += 1
                target_root = cand
        os.makedirs(target_root, exist_ok=True)
    else:
        target_root = os.path.abspath(args.dest) if args.dest else home_dir
        os.makedirs(target_root, exist_ok=True)

    target_root_real = os.path.realpath(target_root)
    restored_count = 0

    try:
        with zipfile.ZipFile(pak_path, "r") as zf:
            for info in zf.infolist():
                if info.filename == MANIFEST_NAME:
                    continue
                is_dir_entry = info.filename.endswith("/") and info.file_size == 0
                clean_rel = info.filename.rstrip("/")
                if not clean_rel:
                    continue
                out_path = ensure_safe_extract_path(target_root_real, clean_rel)

                unix_mode = (info.external_attr >> 16) & 0o170000
                if unix_mode == stat.S_IFLNK:
                    link_target = zf.read(info).decode("utf-8", errors="replace").strip("\x00")
                    os.makedirs(os.path.dirname(out_path), exist_ok=True)
                    if os.path.lexists(out_path):
                        if os.path.isdir(out_path) and not os.path.islink(out_path):
                            shutil.rmtree(out_path)
                        else:
                            os.unlink(out_path)
                    os.symlink(link_target, out_path)
                    restored_count += 1
                elif is_dir_entry or info.is_dir():
                    os.makedirs(out_path, exist_ok=True)
                else:
                    os.makedirs(os.path.dirname(out_path), exist_ok=True)
                    if os.path.islink(out_path):
                        os.unlink(out_path)
                    with zf.open(info, "r") as src_f, open(out_path, "wb") as dst_f:
                        shutil.copyfileobj(src_f, dst_f)
                    perm_bits = (info.external_attr >> 16) & 0o0777
                    if perm_bits:
                        try:
                            os.chmod(out_path, perm_bits)
                        except OSError:
                            pass
                    restored_count += 1
    except Exception as exc:
        fail(f"Restore failed: {exc}", extra={"destDir": target_root})

    emit(
        {
            "ok": True,
            "destDir": target_root,
            "mode": mode,
            "restoredCount": restored_count,
            "folders": check["folders"],
        }
    )


def main():
    parser = argparse.ArgumentParser(prog="paithosh-pak.py")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_create = sub.add_parser("create")
    p_create.add_argument("--home", required=True)
    p_create.add_argument("--store-dir", required=True)
    p_create.add_argument("--exclude-cache", choices=["0", "1"], default="1")
    p_create.add_argument("--folders", nargs="+", required=True)

    p_list = sub.add_parser("list")
    p_list.add_argument("--store-dir", required=True)

    p_inspect = sub.add_parser("inspect")
    p_inspect.add_argument("--file", required=True)

    p_verify = sub.add_parser("verify")
    p_verify.add_argument("--file", required=True)

    p_import = sub.add_parser("import")
    p_import.add_argument("--file", required=True)
    p_import.add_argument("--store-dir", required=True)
    p_import.add_argument("--allow-zip", action="store_true")

    p_restore = sub.add_parser("restore")
    p_restore.add_argument("--file", required=True)
    p_restore.add_argument("--dest", default="")
    p_restore.add_argument("--mode", choices=["staged", "direct"], default="staged")
    p_restore.add_argument("--home", required=True)

    args = parser.parse_args()
    if args.cmd == "create":
        cmd_create(args)
    elif args.cmd == "list":
        cmd_list(args)
    elif args.cmd == "inspect":
        cmd_inspect(args)
    elif args.cmd == "verify":
        cmd_verify(args)
    elif args.cmd == "import":
        cmd_import(args)
    elif args.cmd == "restore":
        cmd_restore(args)


if __name__ == "__main__":
    main()
