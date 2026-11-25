#!/usr/bin/env python3
"""
Semantic normalizer, diff generator, and settings re-applier for Paithosh Hyprland Lua configs.

Distinguishes between:
  - Settings-managed values (edited via Paithosh Settings app: CompositorService,
    KeybindService, paithosh-cursor-gen.py, installer apply.sh autostart toggle)
  - Real user customizations (direct edits, added/removed lines or blocks outside
    Settings-managed keys)
"""

import difflib
import hashlib
import json
import os
import re
import sys


KNOWN_BINDS_HEADERS = {
    "-- Keybindings",
    "-- Keybindings (managed by Paithosh Settings)",
    "-- Core applications & window management",
    "-- Paithosh shell IPC",
    "-- Paithosh Dynamic Island & Shell IPC",
    "-- Focus movement",
    "-- Workspaces 1-10",
    "-- Screenshot (grim + slurp -> clipboard + status bar notification)",
    "-- Screenshot & Capture",
    "-- Capture & Record",
    "-- Screen Recording (wf-recorder toggle -> <=20MB clipboard, >20MB ~/Videos)",
    "-- Cycle workspaces",
    "-- Applications",
    "-- Window & Workspace Management",
    "-- Mouse drag & resize",
    "-- Media & brightness",
    "-- Playerctl",
    "-- Custom Commands & Media",
    "-- Custom Lua (preserved)",
}

CURSOR_ENV_KEYS = (
    "HYPRCURSOR_THEME",
    "HYPRCURSOR_SIZE",
    "XCURSOR_THEME",
    "XCURSOR_SIZE",
)

MONITOR_MANAGED_KEYS = {"output", "mode", "position", "scale", "transform"}

MANAGED_COLOR_KEYS = (
    "pill_bg",
    "surface_bg",
    "surface_raised",
    "text",
    "text_sub",
    "text_muted",
    "border_active_a",
    "border_active_b",
    "border_inactive",
)


def _strip_lua_strings_and_comments(line):
    out = []
    in_q = None
    esc = False
    i = 0
    n = len(line)
    while i < n:
        ch = line[i]
        if esc:
            esc = False
            i += 1
            continue
        if ch == "\\" and in_q:
            esc = True
            i += 1
            continue
        if in_q:
            if ch == in_q:
                in_q = None
            i += 1
            continue
        if ch in ('"', "'"):
            in_q = ch
            out.append(" ")
            i += 1
            continue
        if ch == "-" and i + 1 < n and line[i + 1] == "-":
            break
        out.append(ch)
        i += 1
    return "".join(out)


def _count_block_delta(line):
    clean = _strip_lua_strings_and_comments(line)
    opens = len(re.findall(r"(?<![.:])\b(?:if|do|function|repeat)\b", clean))
    closes = len(re.findall(r"(?<![.:])\b(?:end|until)\b", clean))
    return opens - closes, clean


def _is_managed_bind_line(stripped):
    if not stripped.startswith("hl.bind("):
        return False
    start = stripped.find("(")
    depth = 0
    in_q = None
    esc = False
    end = -1
    for idx in range(start, len(stripped)):
        ch = stripped[idx]
        if esc:
            esc = False
            continue
        if ch == "\\" and in_q:
            esc = True
            continue
        if in_q:
            if ch == in_q:
                in_q = None
            continue
        if ch in ('"', "'"):
            in_q = ch
            continue
        if ch == "(":
            depth += 1
        elif ch == ")":
            depth -= 1
            if depth == 0:
                end = idx
                break
    if end == -1:
        return False
    tail = stripped[end + 1 :].strip()
    if tail and not tail.startswith("--"):
        return False
    return True


def _normalize_animations_line(line, state):
    s = line.strip()
    if re.match(r"^animations\s*=\s*\{", s):
        state["in_animations"] = True
    if state.get("in_animations"):
        if re.match(r"^enabled\s*=\s*(true|false)\s*,?(\s*--.*)?$", s):
            line = re.sub(r"(enabled\s*=\s*)(true|false)", r"\g<1><SETTINGS:animations.enabled>", line, count=1)
        if "}" in s:
            state["in_animations"] = False
    if 'hl.curve("paithoshSpring"' in line:
        line = re.sub(
            r'hl\.curve\("paithoshSpring",\s*\{[^}]*\}\)',
            'hl.curve("paithoshSpring", { type = "spring", mass = 1, stiffness = <SETTINGS:spring.stiffness>, damping = <SETTINGS:spring.damping> })',
            line,
            count=1,
        )
    return line


def _normalize_appearance_line(line, state):
    s = line.strip()
    if re.match(r"^shadow\s*=\s*\{", s):
        state["section"] = "shadow"
    elif re.match(r"^blur\s*=\s*\{", s):
        state["section"] = "blur"
    elif re.match(r"^cursor\s*=\s*\{", s):
        state["section"] = "cursor"

    sec = state.get("section")
    if sec == "shadow":
        line = re.sub(r"(enabled\s*=\s*)(true|false)", r"\g<1><SETTINGS:shadow.enabled>", line, count=1)
        if "}" in s:
            state["section"] = None
        return line
    if sec == "blur":
        line = re.sub(r"(enabled\s*=\s*)(true|false)", r"\g<1><SETTINGS:blur.enabled>", line, count=1)
        line = re.sub(r"(size\s*=\s*)\d+", r"\g<1><SETTINGS:blur.size>", line, count=1)
        line = re.sub(r"(passes\s*=\s*)\d+", r"\g<1><SETTINGS:blur.passes>", line, count=1)
        line = re.sub(r"(vibrancy\s*=\s*)[0-9.]+", r"\g<1><SETTINGS:blur.vibrancy>", line, count=1)
        if "}" in s:
            state["section"] = None
        return line
    if sec == "cursor":
        line = re.sub(r"(enable_hyprcursor\s*=\s*)(true|false)", r"\g<1><SETTINGS:cursor.enable_hyprcursor>", line, count=1)
        line = re.sub(r"(sync_gsettings_theme\s*=\s*)(true|false)", r"\g<1><SETTINGS:cursor.sync_gsettings_theme>", line, count=1)
        if "}" in s:
            state["section"] = None
        return line

    line = re.sub(r"(\bgaps_in\s*=\s*)\d+", r"\g<1><SETTINGS:gaps_in>", line, count=1)
    line = re.sub(r"(\bgaps_out\s*=\s*)\d+", r"\g<1><SETTINGS:gaps_out>", line, count=1)
    line = re.sub(r"(\bborder_size\s*=\s*)\d+", r"\g<1><SETTINGS:border_size>", line, count=1)
    line = re.sub(r'(\blayout\s*=\s*)"[^"]+"', r'\g<1>"<SETTINGS:layout>"', line, count=1)
    line = re.sub(r"(\brounding\s*=\s*)\d+", r"\g<1><SETTINGS:rounding>", line, count=1)
    line = re.sub(r"(\binactive_opacity\s*=\s*)[0-9.]+", r"\g<1><SETTINGS:inactive_opacity>", line, count=1)
    line = re.sub(r"(active_border\s*=\s*\{[^\n]*?\bangle\s*=\s*)\d+", r"\g<1><SETTINGS:active_border.angle>", line, count=1)
    return line


def _normalize_colors_line(line):
    for key in MANAGED_COLOR_KEYS:
        pat = rf'(\b{key}\s*=\s*)"[^"]*"'
        if re.search(pat, line):
            return re.sub(pat, rf'\g<1>"<SETTINGS:colors.{key}>"', line, count=1)
    return line


def _normalize_env_line(line):
    for key in CURSOR_ENV_KEYS:
        pat = r'hl\.env\(\s*["\']' + re.escape(key) + r'["\']\s*,\s*["\'][^"\']*["\']\s*\)'
        if re.search(pat, line):
            return re.sub(pat, f'hl.env("{key}", "<SETTINGS:env.{key}>")', line, count=1)
    return line


def _normalize_autostart_line(line):
    if re.search(r"hl\.exec_cmd\(.*qs\s+-p", line):
        return "<SETTINGS:autostart.qs>"
    return line


def _extract_monitors_non_managed(lines):
    """Return list of (orig_idx, norm_line, raw_line) keeping only non-Settings-managed content."""
    kept = []
    i = 0
    n = len(lines)
    while i < n:
        raw = lines[i]
        s = raw.strip()
        if re.match(r"^hl\.monitor\(\s*\{\s*$", s):
            block = [(i, raw)]
            j = i + 1
            closed = False
            while j < n:
                block.append((j, lines[j]))
                if re.match(r"^\}\s*\)\s*$", lines[j].strip()):
                    closed = True
                    break
                j += 1
            if closed:
                # Check if every inner line is blank, comment, or a managed monitor key
                all_managed = True
                for _, b_raw in block[1:-1]:
                    bs = b_raw.strip()
                    if not bs:
                        continue
                    m = re.match(r"^([a-zA-Z_][a-zA-Z0-9_]*)\s*=", bs)
                    if not m or m.group(1) not in MONITOR_MANAGED_KEYS:
                        all_managed = False
                        break
                if all_managed:
                    i = j + 1
                    continue
        if s == "":
            i += 1
            continue
        kept.append((i, raw, raw))
        i += 1
    return kept


def _extract_binds_non_managed(lines):
    """Return list of (orig_idx, norm_line, raw_line) for non-KeybindService-managed Lua lines."""
    kept = []
    i = 0
    n = len(lines)
    in_long_comment = False
    while i < n:
        raw = lines[i]
        stripped = raw.strip()
        if in_long_comment:
            kept.append((i, raw, raw))
            if "]]" in stripped:
                in_long_comment = False
            i += 1
            continue
        if stripped.startswith("--[["):
            kept.append((i, raw, raw))
            if "]]" not in stripped[4:]:
                in_long_comment = True
            i += 1
            continue
        if not stripped:
            i += 1
            continue
        if stripped in KNOWN_BINDS_HEADERS:
            i += 1
            continue
        if (
            re.match(r"^local\s+programs\s*=\s*require\(", stripped)
            or re.match(r"^local\s+(?:ok_p\s*,\s*)?paithosh\s*=", stripped)
            or re.match(r"^local\s+shellDir\s*=", stripped)
            or re.match(r"^local\s+qsIpc\s*=", stripped)
            or re.match(r"^local\s+mainMod\s*=", stripped)
        ):
            i += 1
            continue

        delta, clean = _count_block_delta(raw)
        if delta > 0:
            block = [(i, raw)]
            depth = delta
            is_shell_quote = bool(re.match(r"^local\s+function\s+shellQuote\b", clean))
            is_ws_for = bool(re.match(r"^for\s+i\s*=\s*1\s*,\s*10\b.*\bdo\b", clean))
            i += 1
            while i < n and depth > 0:
                b_raw = lines[i]
                block.append((i, b_raw))
                b_delta, _ = _count_block_delta(b_raw)
                depth = max(0, depth + b_delta)
                i += 1
            if is_shell_quote or is_ws_for:
                continue
            for idx, b_raw in block:
                kept.append((idx, b_raw, b_raw))
            continue

        if _is_managed_bind_line(stripped):
            i += 1
            continue

        kept.append((i, raw, raw))
        i += 1
    return kept


def normalize_entries(rel, text):
    """
    Returns list of (orig_line_num_1based, norm_line, raw_line) for comparison.
    """
    lines = text.replace("\r\n", "\n").split("\n")
    if lines and lines[-1] == "":
        lines = lines[:-1]

    if rel == "config/monitors.lua":
        return [(idx + 1, norm, raw) for idx, norm, raw in _extract_monitors_non_managed(lines)]
    if rel == "config/binds.lua":
        return [(idx + 1, norm, raw) for idx, norm, raw in _extract_binds_non_managed(lines)]

    state = {}
    out = []
    for idx, raw in enumerate(lines):
        if rel == "config/animations.lua":
            norm = _normalize_animations_line(raw, state)
        elif rel == "config/appearance.lua":
            norm = _normalize_appearance_line(raw, state)
        elif rel == "config/env.lua":
            norm = _normalize_env_line(raw)
        elif rel == "config/autostart.lua":
            norm = _normalize_autostart_line(raw)
        elif rel == "theme/colors.lua":
            norm = _normalize_colors_line(raw)
        else:
            norm = raw
        out.append((idx + 1, norm, raw))
    return out


def norm_sha256(rel, text):
    ent = normalize_entries(rel, text)
    joined = "\n".join(x[1] for x in ent).encode("utf-8")
    return hashlib.sha256(joined).hexdigest()


def has_user_custom_diff(rel, text_a, text_b):
    ent_a = normalize_entries(rel, text_a)
    ent_b = normalize_entries(rel, text_b)
    return [x[1] for x in ent_a] != [x[1] for x in ent_b]


def compute_user_diff(rel, default_text, local_text, max_lines=200):
    ent_a = normalize_entries(rel, default_text)
    ent_b = normalize_entries(rel, local_text)
    norm_a = [x[1] for x in ent_a]
    norm_b = [x[1] for x in ent_b]

    sm = difflib.SequenceMatcher(None, norm_a, norm_b, autojunk=False)
    diff_lines = []
    added_count = 0
    deleted_count = 0
    truncated = False

    for group in sm.get_grouped_opcodes(2):
        # Skip groups that have only equal opcodes
        if all(tag == "equal" for tag, _, _, _, _ in group):
            continue
        first, last = group[0], group[-1]
        a_start = ent_a[first[1]][0] if first[1] < len(ent_a) else (ent_a[-1][0] + 1 if ent_a else 1)
        b_start = ent_b[first[3]][0] if first[3] < len(ent_b) else (ent_b[-1][0] + 1 if ent_b else 1)
        a_len = last[2] - first[1]
        b_len = last[4] - first[3]
        hunk_hdr = f"@@ -{a_start},{a_len} +{b_start},{b_len} @@"
        diff_lines.append({"type": "hunk", "text": hunk_hdr, "line": 0})

        for tag, i1, i2, j1, j2 in group:
            if tag == "equal":
                for idx in range(j1, j2):
                    diff_lines.append({"type": "ctx", "text": " " + ent_b[idx][2], "line": ent_b[idx][0]})
            elif tag in ("replace", "delete"):
                for idx in range(i1, i2):
                    diff_lines.append({"type": "del", "text": "-" + ent_a[idx][2], "line": ent_a[idx][0]})
                    deleted_count += 1
            if tag in ("replace", "insert"):
                for idx in range(j1, j2):
                    diff_lines.append({"type": "add", "text": "+" + ent_b[idx][2], "line": ent_b[idx][0]})
                    added_count += 1

            if len(diff_lines) >= max_lines:
                diff_lines = diff_lines[:max_lines]
                truncated = True
                break
        if truncated:
            break

    return {
        "file": rel,
        "added": added_count,
        "deleted": deleted_count,
        "truncated": truncated,
        "lines": diff_lines,
    }


def reapply_settings(rel, old_cur_text, new_src_text):
    """Carry Settings-managed values from old_cur_text into new_src_text."""
    if rel == "config/animations.lua":
        out = new_src_text
        m = re.search(r"animations\s*=\s*\{[^}]*?enabled\s*=\s*(true|false)", old_cur_text, flags=re.DOTALL)
        if m:
            out = re.sub(
                r"(animations\s*=\s*\{[^}]*?enabled\s*=\s*)(true|false)",
                r"\g<1>" + m.group(1),
                out,
                count=1,
                flags=re.DOTALL,
            )
        m = re.search(r'hl\.curve\("paithoshSpring",\s*\{[^}]*\}\)', old_cur_text)
        if m:
            out = re.sub(r'hl\.curve\("paithoshSpring",\s*\{[^}]*\}\)', lambda _: m.group(0), out, count=1)
        return out

    if rel == "config/appearance.lua":
        out = new_src_text
        simple_pats = [
            (r"(\bgaps_in\s*=\s*)(\d+)", r"\g<1>"),
            (r"(\bgaps_out\s*=\s*)(\d+)", r"\g<1>"),
            (r"(\bborder_size\s*=\s*)(\d+)", r"\g<1>"),
            (r'(\blayout\s*=\s*)"([^"]+)"', r'\g<1>"'),
            (r"(\brounding\s*=\s*)(\d+)", r"\g<1>"),
            (r"(\binactive_opacity\s*=\s*)([0-9.]+)", r"\g<1>"),
        ]
        for pat, prefix in simple_pats:
            m = re.search(pat, old_cur_text)
            if m:
                val = m.group(2)
                if prefix.endswith('"'):
                    out = re.sub(pat, prefix + val + '"', out, count=1)
                else:
                    out = re.sub(pat, prefix + val, out, count=1)
        m = re.search(r"shadow\s*=\s*\{[^}]*?enabled\s*=\s*(true|false)", old_cur_text, flags=re.DOTALL)
        if m:
            out = re.sub(
                r"(shadow\s*=\s*\{[^}]*?enabled\s*=\s*)(true|false)",
                r"\g<1>" + m.group(1),
                out,
                count=1,
                flags=re.DOTALL,
            )
        m = re.search(r"blur\s*=\s*\{[^}]*\}", old_cur_text, flags=re.DOTALL)
        if m:
            out = re.sub(r"blur\s*=\s*\{[^}]*\}", lambda _: m.group(0), out, count=1, flags=re.DOTALL)
        m_cur = re.search(r"cursor\s*=\s*\{([^}]*)\}", old_cur_text, flags=re.DOTALL)
        if m_cur:
            cur_blk = m_cur.group(1)
            for key in ("enable_hyprcursor", "sync_gsettings_theme"):
                km = re.search(key + r"\s*=\s*(true|false)", cur_blk)
                if km:
                    out = re.sub(
                        r"(cursor\s*=\s*\{[^}]*?" + key + r"\s*=\s*)(true|false)",
                        r"\g<1>" + km.group(1),
                        out,
                        count=1,
                        flags=re.DOTALL,
                    )
        m_ang = re.search(r"active_border\s*=\s*\{(?:[^{}]|\{[^{}]*\})*?\bangle\s*=\s*(\d+)", old_cur_text)
        if m_ang:
            out = re.sub(
                r"(active_border\s*=\s*\{(?:[^{}]|\{[^{}]*\})*?\bangle\s*=\s*)\d+",
                r"\g<1>" + m_ang.group(1),
                out,
                count=1,
            )
        return out

    if rel == "theme/colors.lua":
        out = new_src_text
        for key in MANAGED_COLOR_KEYS:
            pat = rf'(\b{key}\s*=\s*)"([^"]*)"'
            m = re.search(pat, old_cur_text)
            if m:
                out = re.sub(pat, lambda mm, v=m.group(2): mm.group(1) + f'"{v}"', out, count=1)
        return out

    if rel == "config/env.lua":
        out = new_src_text
        for key in CURSOR_ENV_KEYS:
            pat = r'hl\.env\(\s*["\']' + re.escape(key) + r'["\']\s*,\s*["\']([^"\']*)["\']\s*\)'
            m = re.search(pat, old_cur_text)
            if m:
                repl = f'hl.env("{key}", "{m.group(1)}")'
                if re.search(pat, out):
                    out = re.sub(pat, lambda _: repl, out, count=1)
                else:
                    sep = "" if (not out or out.endswith("\n")) else "\n"
                    out += f"{sep}{repl}\n"
        return out

    if rel == "config/monitors.lua":
        # Preserve managed monitor blocks from old_cur_text
        blocks = re.findall(r"hl\.monitor\(\s*\{[^}]*\}\s*\)", old_cur_text, flags=re.DOTALL)
        if blocks:
            header_lines = [l for l in new_src_text.splitlines() if l.strip().startswith("--")]
            header = ("\n".join(header_lines) + "\n\n") if header_lines else ""
            return header + "\n\n".join(blocks) + "\n"
        return new_src_text

    if rel == "config/autostart.lua":
        m = re.search(r"^[ \t]*(--[ \t]*)?hl\.exec_cmd\(.*qs\s+-p.*$", old_cur_text, flags=re.MULTILINE)
        if m:
            return re.sub(
                r"^[ \t]*(--[ \t]*)?hl\.exec_cmd\(.*qs\s+-p.*$",
                lambda _: m.group(0),
                new_src_text,
                count=1,
                flags=re.MULTILINE,
            )
        return new_src_text

    return new_src_text


def main():
    if len(sys.argv) < 2:
        sys.exit(2)
    cmd = sys.argv[1]

    if cmd == "diff":
        if len(sys.argv) < 5:
            sys.exit(2)
        src_file, cur_file, rel = sys.argv[2], sys.argv[3], sys.argv[4]
        try:
            src_txt = open(src_file, "r", encoding="utf-8").read()
            cur_txt = open(cur_file, "r", encoding="utf-8").read()
        except OSError as e:
            print(json.dumps({"error": str(e), "lines": []}))
            sys.exit(1)
        print(json.dumps(compute_user_diff(rel, src_txt, cur_txt)))
        return

    if cmd == "reapply":
        if len(sys.argv) < 6:
            sys.exit(2)
        old_cur, new_src, rel, out_file = sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]
        old_txt = open(old_cur, "r", encoding="utf-8").read()
        src_txt = open(new_src, "r", encoding="utf-8").read()
        merged = reapply_settings(rel, old_txt, src_txt)
        with open(out_file, "w", encoding="utf-8") as f:
            f.write(merged)
        return

    if cmd == "norm-manifest":
        if len(sys.argv) < 4:
            sys.exit(2)
        src_dir, out_manifest = sys.argv[2], sys.argv[3]
        entries = []
        for base, _, files in os.walk(src_dir):
            for fn in files:
                full = os.path.join(base, fn)
                rel = os.path.relpath(full, src_dir).replace(os.sep, "/")
                if rel == "config/paithosh.lua":
                    continue
                txt = open(full, "r", encoding="utf-8").read()
                entries.append((rel, norm_sha256(rel, txt)))
        entries.sort(key=lambda x: x[0])
        with open(out_manifest, "w", encoding="utf-8") as mf:
            for rel, digest in entries:
                mf.write(f"{digest}  {rel}\n")
        return

    sys.exit(2)


if __name__ == "__main__":
    main()
