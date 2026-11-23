#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PAK_PY="$SCRIPT_DIR/paithosh-pak.py"
BTRFS_SH="$SCRIPT_DIR/paithosh-btrfs.sh"

TMP_ROOT="$(mktemp -d /tmp/paithosh-backup-test.XXXXXX)"
SOCK_PID=""
cleanup() {
    if [ -n "$SOCK_PID" ]; then
        kill "$SOCK_PID" 2>/dev/null || true
    fi
    rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

echo "[0/5] Checking script syntax..."
bash -n "$BTRFS_SH"
python3 -m py_compile "$PAK_PY"

MOCK_HOME="$TMP_ROOT/home"
MOCK_STORE="$TMP_ROOT/store"
MOCK_RESTORE="$TMP_ROOT/restored"
MOCK_EXT="$TMP_ROOT/external"
MOCK_SYS="$TMP_ROOT/system"
mkdir -p "$MOCK_HOME/Documents" "$MOCK_HOME/Projects/demo/.git/objects/ab" "$MOCK_HOME/Projects/demo/node_modules/pkg" "$MOCK_HOME/.config/app" "$MOCK_STORE" "$MOCK_RESTORE" "$MOCK_EXT" "$MOCK_SYS"

printf 'hello backup\n' > "$MOCK_HOME/Documents/note.txt"
printf 'git-object-data\n' > "$MOCK_HOME/Projects/demo/.git/objects/ab/cdef123"
printf 'module.exports = 1;\n' > "$MOCK_HOME/Projects/demo/node_modules/pkg/index.js"
printf '{"theme":"nord"}\n' > "$MOCK_HOME/.config/app/conf.json"
ln -s "conf.json" "$MOCK_HOME/.config/app/conf-link.json"

python3 -c '
import os, socket, sys, time
p = sys.argv[1]
s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
s.bind(p)
s.listen(1)
time.sleep(15)
' "$MOCK_HOME/.config/app/test.sock" &
SOCK_PID=$!
for _ in $(seq 1 20); do
    [ -S "$MOCK_HOME/.config/app/test.sock" ] && break
    sleep 0.05
done
[ -S "$MOCK_HOME/.config/app/test.sock" ]

echo "[1/5] Testing .pak create, .git/objects preservation, socket skip & CRC-32..."
CREATE_JSON="$(python3 "$PAK_PY" create --home "$MOCK_HOME" --store-dir "$MOCK_STORE" --exclude-cache 1 --folders Documents Projects .config)"
PAK_PATH="$(python3 -c '
import hashlib, json, sys
lines = [l for l in sys.argv[1].splitlines() if l.startswith("{")]
d = json.loads(lines[-1])
assert d["ok"] is True, d
assert d["name"].endswith(".pak"), d
assert d["crcOk"] is True, d
assert d["skippedCount"] >= 1, d
assert any("test.sock" in s for s in d["skippedSample"]), d
h = hashlib.sha256(open(d["path"], "rb").read()).hexdigest()
assert d["sha256"] == h, (d["sha256"], h)
print(d["path"])
' "$CREATE_JSON")"

unzip -t "$PAK_PATH" >/dev/null
ENTRIES="$(unzip -Z1 "$PAK_PATH")"
grep -qx "Projects/demo/.git/objects/ab/cdef123" <<<"$ENTRIES"
if grep -q "node_modules" <<<"$ENTRIES"; then
    echo "FAIL: node_modules was not excluded" >&2
    exit 1
fi
grep -qx ".paithosh-pak.json" <<<"$ENTRIES"
echo "  PASS: .pak created, CRC-32 OK, .git/objects intact, node_modules excluded, socket skipped"

echo "[2/5] Testing .pak store listing & plain .zip renamed to .pak compatibility..."
mkdir -p "$MOCK_EXT/src/Documents"
printf 'plain zip payload\n' > "$MOCK_EXT/src/Documents/plain.txt"
(cd "$MOCK_EXT/src" && zip -q "$MOCK_EXT/external-plain.pak" -r Documents)
python3 "$PAK_PY" inspect --file "$MOCK_EXT/external-plain.pak" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["ok"] is True and d["isZip"] is True and d["hasManifest"] is False and "Documents" in d["folders"], d
'
python3 "$PAK_PY" verify --file "$MOCK_EXT/external-plain.pak" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["ok"] is True and d["crcOk"] is True and d["sha256"], d
'
python3 "$PAK_PY" import --file "$MOCK_EXT/external-plain.pak" --store-dir "$MOCK_STORE" >/dev/null
python3 "$PAK_PY" list --store-dir "$MOCK_STORE" | python3 -c '
import json, sys
d = json.load(sys.stdin)
assert d["ok"] is True and len(d["items"]) == 2, d
names = {it["name"] for it in d["items"]}
assert "external-plain.pak" in names, names
'
echo "  PASS: plain .zip->.pak inspect, verify, import & store list passed"

echo "[3/5] Testing Zip-Slip, escaping symlink & corrupt CRC rejection..."
python3 -c '
import stat, sys, zipfile
slip_pak, sym_pak = sys.argv[1], sys.argv[2]
with zipfile.ZipFile(slip_pak, "w") as zf:
    zf.writestr("../../pwned.txt", "evil")
with zipfile.ZipFile(sym_pak, "w") as zf:
    zi = zipfile.ZipInfo("Documents/badlink")
    zi.external_attr = (stat.S_IFLNK | 0o777) << 16
    zf.writestr(zi, b"/etc/passwd")
' "$MOCK_EXT/slip.pak" "$MOCK_EXT/sym.pak"

for bad_pak in "$MOCK_EXT/slip.pak" "$MOCK_EXT/sym.pak"; do
    if python3 "$PAK_PY" verify --file "$bad_pak" >/dev/null 2>&1; then
        echo "FAIL: verify accepted unsafe pak $bad_pak" >&2
        exit 1
    fi
    if python3 "$PAK_PY" restore --file "$bad_pak" --dest "$MOCK_RESTORE" --mode staged --home "$MOCK_HOME" >/dev/null 2>&1; then
        echo "FAIL: restore accepted unsafe pak $bad_pak" >&2
        exit 1
    fi
done
[ ! -e "$TMP_ROOT/pwned.txt" ]

cp "$PAK_PATH" "$MOCK_EXT/corrupt.pak"
python3 -c '
import sys
p = sys.argv[1]
data = bytearray(open(p, "rb").read())
data[len(data) // 2] ^= 0xFF
open(p, "wb").write(data)
' "$MOCK_EXT/corrupt.pak"
if python3 "$PAK_PY" verify --file "$MOCK_EXT/corrupt.pak" >/dev/null 2>&1; then
    echo "FAIL: verify accepted byte-corrupted pak" >&2
    exit 1
fi
echo "  PASS: Zip-Slip, escaping symlink & corrupt CRC rejected cleanly"

echo "[4/5] Testing safe staged restore (no silent overwrite)..."
R1_JSON="$(python3 "$PAK_PY" restore --file "$PAK_PATH" --dest "$MOCK_RESTORE" --mode staged --home "$MOCK_HOME")"
R2_JSON="$(python3 "$PAK_PY" restore --file "$PAK_PATH" --dest "$MOCK_RESTORE" --mode staged --home "$MOCK_HOME")"
python3 -c '
import json, os, sys
r1, r2 = json.loads(sys.argv[1]), json.loads(sys.argv[2])
assert r1["ok"] and r2["ok"]
assert r1["destDir"] != r2["destDir"], (r1["destDir"], r2["destDir"])
for d in (r1["destDir"], r2["destDir"]):
    assert open(os.path.join(d, "Documents/note.txt")).read() == "hello backup\n"
    assert open(os.path.join(d, "Projects/demo/.git/objects/ab/cdef123")).read() == "git-object-data\n"
    assert os.path.islink(os.path.join(d, ".config/app/conf-link.json"))
' "$R1_JSON" "$R2_JSON"
echo "  PASS: staged restore preserves content, .git/objects, symlinks & never overwrites"

echo "[5/5] Testing paithosh-btrfs.sh probe & ID safety guard..."
PROBE_OUT="$("$BTRFS_SH" probe --sys-dir "$MOCK_SYS")"
python3 -c '
import json, sys
lines = [l for l in sys.argv[1].splitlines() if l.startswith("RESULT|")]
assert len(lines) == 1, sys.argv[1]
d = json.loads(lines[0][7:])
assert d["ok"] is True, d
env = d["env"]
assert env["isBtrfsRoot"] is True, env
assert env["rootSubvol"] == "root", env
assert env["homeSeparateSubvol"] is True, env
assert env["bootSeparate"] is True, env
assert bool(env["kernelRunning"]), env
assert env["vmlinuzExists"] is True, env
' "$PROBE_OUT"

if "$BTRFS_SH" delete --id "../evil" --sys-dir "$MOCK_SYS" >/dev/null 2>&1; then
    echo "FAIL: paithosh-btrfs.sh accepted unsafe ID" >&2
    exit 1
fi
echo "  PASS: Btrfs probe & ID validation passed"
echo "ALL BACKUP & RESTORE TESTS PASSED"
