#!/usr/bin/env python3
"""
Fix HCP Swift file references: resolve paths from the group tree (PBXGroup `path`
only, not display `name`), then update or remove PBXFileReference entries.
"""
from __future__ import annotations

import os
import re
import string
import sys
from pathlib import Path

# PBX unquoted tokens are strict; paths with +, @, etc. must be quoted.
_PBX_PATH_SAFE = set(string.ascii_letters + string.digits + "/._-")

REPO = Path(__file__).resolve().parents[1]
PBX = REPO / "HCP.xcodeproj" / "project.pbxproj"
SEARCH_DIRS = (
    "Signal",
    "SignalUI",
    "SignalNSE",
    "SignalShareExtension",
    "SignalServiceKit",
    "SignalTests",
    "SignalUITests",
)

FILE_REF_LINE_RE = re.compile(
    r"^(\t\t)([A-F0-9]{24})( /\* )([^*]+)( \*/ = \{isa = PBXFileReference;)([^\n]+)(\};)$",
    re.MULTILINE,
)


def extract_object_block(text: str, gid: str) -> str | None:
    for pattern in (
        rf"^\t\t{re.escape(gid)} /\* [^*]+ \*/ = {{\n",
        rf"^\t\t{re.escape(gid)} = {{\n",
    ):
        m = re.search(pattern, text, re.MULTILINE)
        if not m:
            continue
        j = text.find("{", m.start(), m.end())
        depth = 0
        k = j
        while k < len(text):
            if text[k] == "{":
                depth += 1
            elif text[k] == "}":
                depth -= 1
                if depth == 0:
                    end = text.find("\n", k) + 1
                    return text[m.start() : end]
            k += 1
    return None


def extract_children_ids(block: str) -> list[str]:
    pos = block.find("children = (")
    if pos < 0:
        return []
    pos = block.find("\n", pos) + 1
    ids: list[str] = []
    while pos < len(block):
        line_end = block.find("\n", pos)
        if line_end < 0:
            break
        line = block[pos:line_end]
        pos = line_end + 1
        if re.match(r"\s+\);", line):
            break
        m = re.search(r"([A-F0-9]{24}) /\*", line)
        if m:
            ids.append(m.group(1))
    return ids


def strip_path_value(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
        return s[1:-1]
    return s


def group_fs_segment(block: str) -> str | None:
    pm = re.search(r"path = ([^;\n]+);", block)
    if not pm:
        return None
    return strip_path_value(pm.group(1))


def load_containers(text: str) -> dict[str, tuple[list[str], str | None]]:
    containers: dict[str, tuple[list[str], str | None]] = {}
    for sec_name in ("PBXGroup", "PBXVariantGroup"):
        sm = re.search(
            rf"/\* Begin {sec_name} section \*/\n(.*?)\n/\* End {sec_name} section \*/",
            text,
            re.DOTALL,
        )
        if not sm:
            continue
        sec = sm.group(1)
        for m in re.finditer(r"^\t\t([A-F0-9]{24})( /\* [^*]+ \*/)? = \{\n", sec, re.MULTILINE):
            gid = m.group(1)
            block = extract_object_block(text, gid)
            if not block or f"isa = {sec_name};" not in block:
                continue
            ch = extract_children_ids(block)
            seg = group_fs_segment(block)
            containers[gid] = (ch, seg)
    return containers


def load_file_ref_lines(text: str) -> dict[str, str]:
    sm = re.search(
        r"/\* Begin PBXFileReference section \*/\n(.*?)\n/\* End PBXFileReference section \*/",
        text,
        re.DOTALL,
    )
    if not sm:
        raise SystemExit("PBXFileReference section missing")
    out: dict[str, str] = {}
    for line in sm.group(1).splitlines():
        m = FILE_REF_LINE_RE.match(line)
        if m:
            uid_m = re.match(r"\t\t([A-F0-9]{24}) ", line)
            if uid_m:
                out[uid_m.group(1)] = line
    return out


def ref_path_segment(line: str) -> str:
    m = re.match(r"\t\t[A-F0-9]{24} /\* ([^*]+) \*/ = \{(.+)\};$", line)
    if not m:
        raise ValueError(line[:80])
    body = m.group(2)
    pm = re.search(r"path = ([^;]+);", body)
    nm = re.search(r"name = ([^;]+);", body)
    if pm:
        return strip_path_value(pm.group(1))
    if nm:
        return strip_path_value(nm.group(1))
    return m.group(1).strip()


def parse_main_group(text: str) -> str:
    m = re.search(r"\t\t\tmainGroup = ([A-F0-9]{24});", text)
    if not m:
        raise SystemExit("mainGroup missing")
    return m.group(1)


def resolved_paths_from_tree(
    text: str,
    containers: dict[str, tuple[list[str], str | None]],
    filerefs: dict[str, str],
) -> dict[str, str]:
    main = parse_main_group(text)
    out: dict[str, str] = {}

    def walk(gid: str, parts: list[str]) -> None:
        if gid not in containers:
            return
        ch, seg = containers[gid]
        full = parts + ([seg] if seg else [])
        for cid in ch:
            if cid in filerefs:
                out[cid] = "/".join(full + [ref_path_segment(filerefs[cid])])
            elif cid in containers:
                walk(cid, full)

    walk(main, [])
    return out


def basename_hits(ext: str) -> dict[str, list[Path]]:
    out: dict[str, list[Path]] = {}
    for d in SEARCH_DIRS:
        root = REPO / d
        if not root.is_dir():
            continue
        for p in root.rglob(f"*{ext}"):
            out.setdefault(p.name, []).append(p)
    return out


def format_pbx_path(rel_posix: str) -> str:
    if all(c in _PBX_PATH_SAFE for c in rel_posix):
        return rel_posix
    esc = rel_posix.replace("\\", "\\\\").replace('"', '\\"')
    return f'"{esc}"'


def main() -> int:
    text = PBX.read_text()
    containers = load_containers(text)
    filerefs = load_file_ref_lines(text)
    tree_paths = resolved_paths_from_tree(text, containers, filerefs)
    swift_hits = basename_hits(".swift")
    header_hits = basename_hits(".h")

    to_remove: set[str] = set()
    replacements: list[tuple[str, str]] = []

    for m in FILE_REF_LINE_RE.finditer(text):
        uid = m.group(2)
        comment = m.group(4).strip()
        body = m.group(6)
        if "sourcecode.swift" in body:
            hits = swift_hits
            want_ext = ".swift"
        elif "sourcecode.c.h" in body:
            hits = header_hits
            want_ext = ".h"
        else:
            continue

        logical = tree_paths.get(uid)
        base = Path(comment).name if comment.endswith(want_ext) else None
        if not base:
            pm = re.search(r"path = ([^;]+);", body)
            base = Path(strip_path_value(pm.group(1))).name if pm else None
        if not base:
            continue

        cands = hits.get(base, [])

        if logical:
            p = REPO / logical
            if p.is_file():
                continue
        else:
            p = REPO / base
            if p.is_file():
                continue

        if len(cands) == 0:
            to_remove.add(uid)
            continue
        if len(cands) > 1:
            print(f"ambiguous {base!r} ({len(cands)} files); removing ref", file=sys.stderr)
            to_remove.add(uid)
            continue

        correct = cands[0]
        parent_parts = logical.split("/")[:-1] if logical else []
        parent_fs = REPO.joinpath(*parent_parts) if parent_parts else REPO
        if not parent_fs.is_dir():
            to_remove.add(uid)
            continue
        try:
            rel = os.path.relpath(correct, parent_fs).replace(os.sep, "/")
        except ValueError:
            to_remove.add(uid)
            continue
        if not rel or rel.startswith("/"):
            to_remove.add(uid)
            continue
        if not re.search(r"path = ([^;]+);", body):
            to_remove.add(uid)
            continue

        new_body = re.sub(
            r"path = ([^;]+);",
            f"path = {format_pbx_path(rel)};",
            body,
            count=1,
        )
        old_line = m.group(0)
        new_line = (
            m.group(1)
            + m.group(2)
            + m.group(3)
            + m.group(4)
            + m.group(5)
            + new_body
            + m.group(7)
        )
        replacements.append((old_line, new_line))

    for old, new in replacements:
        text = text.replace(old, new, 1)

    build_file_line_re = re.compile(
        r"^\t\t([A-F0-9]{24}) /\* [^*]+ \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})[^\n]*\n",
        re.MULTILINE,
    )
    to_remove_build: set[str] = set()
    for m in build_file_line_re.finditer(text):
        if m.group(2) in to_remove:
            to_remove_build.add(m.group(1))

    removed_build = 0
    out_lines: list[str] = []
    for line in text.splitlines(keepends=True):
        bm = build_file_line_re.match(line)
        if bm and bm.group(1) in to_remove_build:
            removed_build += 1
            continue
        out_lines.append(line)
    text = "".join(out_lines)

    phase_sources_re = re.compile(
        r"^\t\t\t\t([A-F0-9]{24}) /\* [^*]+ in Sources \*/,?\n"
    )
    phase_headers_re = re.compile(
        r"^\t\t\t\t([A-F0-9]{24}) /\* [^*]+ in Headers \*/,?\n"
    )
    removed_phase_src = 0
    removed_phase_hdr = 0
    out3: list[str] = []
    for line in text.splitlines(keepends=True):
        pm = phase_sources_re.match(line)
        if pm and pm.group(1) in to_remove_build:
            removed_phase_src += 1
            continue
        pmh = phase_headers_re.match(line)
        if pmh and pmh.group(1) in to_remove_build:
            removed_phase_hdr += 1
            continue
        out3.append(line)
    text = "".join(out3)

    ref_block_re = re.compile(
        r"^\t\t([A-F0-9]{24}) /\* [^*]+ \*/ = \{isa = PBXFileReference;[^\n]+\};\n",
        re.MULTILINE,
    )
    removed_ref = 0
    out4: list[str] = []
    for line in text.splitlines(keepends=True):
        rm = ref_block_re.match(line)
        if rm and rm.group(1) in to_remove:
            removed_ref += 1
            continue
        out4.append(line)
    text = "".join(out4)

    # Do not strip group/build-phase lines by regex; other sections use the same shape.

    PBX.write_text(text)
    print(
        f"fix_hcp_pbx: path fixes {len(replacements)}, "
        f"removed fileRefs {removed_ref}, buildFiles {removed_build}, "
        f"sources phase lines {removed_phase_src}, headers phase lines {removed_phase_hdr}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
