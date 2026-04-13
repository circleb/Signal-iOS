#!/usr/bin/env python3
"""
Copy PBXFileReference *definitions* from upstream Signal's project.pbxproj into
HCP.xcodeproj, matched by logical tree path (not by UUID).

UUIDs stay HCP-local; only the { isa = PBXFileReference; ... } payload is replaced
when the file's path-in-group-tree matches upstream.

Run from repo root (after committing or staging Signal.xcodeproj in git if needed):
  python3 Scripts/sync_pbx_file_refs_from_signal.py
  python3 Scripts/sync_pbx_file_refs_from_signal.py --dry-run

Env:
  SIGNAL_PBX_SPEC   override for git path (default: HEAD:Signal.xcodeproj/project.pbxproj)

Typical workflow with the group syncer:
  python3 Scripts/sync_ssk_groups_from_signal_pbx.py
  python3 Scripts/sync_pbx_file_refs_from_signal.py
"""
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HCP_PBX = REPO / "HCP.xcodeproj" / "project.pbxproj"
DEFAULT_SIGNAL_SPEC = "HEAD:Signal.xcodeproj/project.pbxproj"

FILE_REF_LINE_RE = re.compile(
    r"^(\t\t[A-F0-9]{24} /\* [^*]+ \*/ = )(\{.*\});$",
)


def git_show_pbx(spec: str) -> str:
    return subprocess.check_output(
        ["git", "show", f"{spec}"],
        cwd=REPO,
        text=True,
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


def parse_children_and_segment(block: str) -> tuple[list[str], str | None]:
    """PBXGroup path segment: only `path =` affects on-disk layout; `name` alone is virtual."""
    ch = extract_children_ids(block)
    pm = re.search(r"path = ([^;\n]+);", block)

    def stripv(s: str) -> str:
        s = s.strip()
        if len(s) >= 2 and s[0] == '"' and s[-1] == '"':
            return s[1:-1]
        return s

    seg: str | None = stripv(pm.group(1)) if pm else None
    return ch, seg


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
            containers[gid] = parse_children_and_segment(block)
    return containers


def load_file_ref_lines(text: str) -> dict[str, str]:
    sm = re.search(
        r"/\* Begin PBXFileReference section \*/\n(.*?)\n/\* End PBXFileReference section \*/",
        text,
        re.DOTALL,
    )
    if not sm:
        raise ValueError("PBXFileReference section not found")
    out: dict[str, str] = {}
    for line in sm.group(1).splitlines():
        m = FILE_REF_LINE_RE.match(line)
        if m:
            uid = re.match(r"\t\t([A-F0-9]{24}) ", line)
            if uid:
                out[uid.group(1)] = line
    return out


def ref_segment(line: str) -> str:
    m = re.match(r"\t\t[A-F0-9]{24} /\* ([^*]+) \*/ = \{(.+)\};$", line)
    if not m:
        raise ValueError(f"bad file ref line: {line[:80]}")
    body = m.group(2)
    pm = re.search(r"path = ([^;]+);", body)
    nm = re.search(r"name = ([^;]+);", body)

    def stripv(s: str) -> str:
        return s.strip().strip('"')

    if pm:
        return stripv(pm.group(1))
    if nm:
        return stripv(nm.group(1))
    return m.group(1).strip()


def parse_main_group(text: str) -> str:
    m = re.search(r"\t\t\tmainGroup = ([A-F0-9]{24});", text)
    if not m:
        raise ValueError("mainGroup not found")
    return m.group(1)


def file_ref_id_to_logical_path(text: str) -> tuple[dict[str, str], list[tuple[str, str]]]:
    containers = load_containers(text)
    filerefs = load_file_ref_lines(text)
    main = parse_main_group(text)
    out: dict[str, str] = {}
    ambiguous: list[tuple[str, str]] = []

    def walk(gid: str, parts: list[str]) -> None:
        if gid not in containers:
            return
        ch, seg = containers[gid]
        full = parts + ([seg] if seg else [])
        for cid in ch:
            if cid in filerefs:
                key = "/".join(full + [ref_segment(filerefs[cid])])
                if cid in out and out[cid] != key:
                    ambiguous.append((cid, f"{out[cid]!r} vs {key!r}"))
                out[cid] = key
            elif cid in containers:
                walk(cid, full)

    walk(main, [])
    return out, ambiguous


def build_key_to_signal_body(signal_text: str) -> dict[str, str]:
    id_to_key, _ = file_ref_id_to_logical_path(signal_text)
    filerefs = load_file_ref_lines(signal_text)
    key_to_body: dict[str, str] = {}
    for uid, key in id_to_key.items():
        line = filerefs[uid]
        m = FILE_REF_LINE_RE.match(line)
        if not m:
            continue
        body = m.group(2)
        if key in key_to_body and key_to_body[key] != body:
            raise ValueError(f"duplicate logical key with different bodies: {key!r}")
        key_to_body[key] = body
    return key_to_body


def sync_hcp(
    hcp_text: str,
    key_to_signal_body: dict[str, str],
    dry_run: bool,
) -> tuple[str, int, int, list[str]]:
    id_to_key, ambiguous = file_ref_id_to_logical_path(hcp_text)
    sm = re.search(
        r"/\* Begin PBXFileReference section \*/\n(.*?)\n/\* End PBXFileReference section \*/",
        hcp_text,
        re.DOTALL,
    )
    if not sm:
        raise ValueError("HCP PBXFileReference section not found")
    section = sm.group(1)
    lines_out: list[str] = []
    updated = 0
    skipped_no_upstream = 0
    notes: list[str] = []
    for cid, msg in ambiguous:
        notes.append(f"ambiguous file ref placement {cid}: {msg}")
    for line in section.splitlines():
        m = FILE_REF_LINE_RE.match(line)
        if not m:
            lines_out.append(line)
            continue
        uid_m = re.match(r"\t\t([A-F0-9]{24}) ", line)
        uid = uid_m.group(1) if uid_m else ""
        key = id_to_key.get(uid)
        prefix, old_body = m.group(1), m.group(2)
        if not key:
            lines_out.append(line)
            continue
        upstream_body = key_to_signal_body.get(key)
        if upstream_body is None:
            skipped_no_upstream += 1
            lines_out.append(line)
            continue
        if upstream_body == old_body:
            lines_out.append(line)
            continue
        updated += 1
        lines_out.append(prefix + upstream_body + ";")
    new_section = "\n".join(lines_out)
    new_text = (
        hcp_text[: sm.start(1)] + new_section + hcp_text[sm.end(1) :]
    )
    return new_text, updated, skipped_no_upstream, notes


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument(
        "--dry-run",
        action="store_true",
        help="print stats only; do not write HCP.xcodeproj",
    )
    ap.add_argument(
        "--signal-spec",
        default=os.environ.get("SIGNAL_PBX_SPEC", DEFAULT_SIGNAL_SPEC),
        help=f"git show argument (default: {DEFAULT_SIGNAL_SPEC})",
    )
    args = ap.parse_args()

    try:
        signal_text = git_show_pbx(args.signal_spec)
    except subprocess.CalledProcessError as e:
        print(
            "Could not read Signal project from git:",
            args.signal_spec,
            e,
            file=sys.stderr,
        )
        return 1

    hcp_text = HCP_PBX.read_text()
    try:
        key_to_body = build_key_to_signal_body(signal_text)
    except ValueError as e:
        print(e, file=sys.stderr)
        return 1

    new_text, updated, skipped, notes = sync_hcp(
        hcp_text, key_to_body, dry_run=args.dry_run
    )
    for n in notes:
        print(n, file=sys.stderr)
    print(
        f"sync_pbx_file_refs: updated {updated} file refs; "
        f"{skipped} HCP refs had no matching upstream path"
    )
    if args.dry_run:
        return 0
    if new_text != hcp_text:
        HCP_PBX.write_text(new_text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
