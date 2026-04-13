#!/usr/bin/env python3
"""
Replace SignalServiceKit-related PBXGroup blocks in HCP.xcodeproj with upstream
(Signal) definitions from git, preserving the HCP Account group.

Run from repo root:
  python3 Scripts/sync_ssk_groups_from_signal_pbx.py

For PBXFileReference lines (matched by tree path, not UUID), run:
  python3 Scripts/sync_pbx_file_refs_from_signal.py
Or both: Scripts/sync_pbx_from_signal.sh

Requires: git show HEAD:Signal.xcodeproj/project.pbxproj
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
HCP_PBX = REPO / "HCP.xcodeproj" / "project.pbxproj"
ACCOUNT_GID = "F9C5C9BA289453B100548EEE"
NOTIFICATIONS_GID = "88D23D0823CEBF4400B0E74B"
# HCP-only sources under SignalServiceKit/Notifications (not in upstream Signal).
HCP_NOTIFICATIONS_EXTRA_REFS = (
    "B524D39C2E430639004B1E4D",  # StoredNonSignalNotification.swift
    "B524D39D2E430639004B1E4D",  # NonSignalNotificationStore.swift
)
SSK_ROOT = "F9C5C898289451B900548EEE"


def git_signal_pbx() -> str:
    return subprocess.check_output(
        ["git", "show", "HEAD:Signal.xcodeproj/project.pbxproj"],
        cwd=REPO,
        text=True,
    )


def ssk_top_children(lines: list[str]) -> list[str]:
    in_ssk = False
    in_children = False
    out: list[str] = []
    for line in lines:
        if f"{SSK_ROOT} /* SignalServiceKit */ = {{" in line:
            in_ssk = True
            continue
        if in_ssk and "children = (" in line:
            in_children = True
            continue
        if in_children:
            if line.strip() == ");":
                break
            m = re.match(r"\t\t\t\t([A-F0-9]{24}) /\*", line)
            if m:
                out.append(m.group(1))
    return out


def parse_groups(text: str) -> dict[str, list[str]]:
    groups: dict[str, list[str]] = {}
    for m in re.finditer(
        r"^\t\t([A-F0-9]{24}) /\* [^*]+ \*/ = \{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = \(\n",
        text,
        re.MULTILINE,
    ):
        gid = m.group(1)
        start = m.end()
        end = text.find("\t\t\t);", start)
        if end == -1:
            continue
        block = text[start:end]
        children = re.findall(r"^\t\t\t\t([A-F0-9]{24}) /\*", block, re.MULTILINE)
        groups[gid] = children
    return groups


def collect_ssk_group_ids(sig: str) -> list[str]:
    roots = ssk_top_children(sig.splitlines())
    gs = parse_groups(sig)
    seen: set[str] = set()
    order: list[str] = []
    stack = list(roots)
    while stack:
        g = stack.pop()
        if g in seen or g not in gs:
            continue
        seen.add(g)
        order.append(g)
        for c in gs[g]:
            if c in gs:
                stack.append(c)
    return order


def extract_group_block(text: str, gid: str) -> str | None:
    m = re.search(
        rf"^\t\t{re.escape(gid)} /\* [^*]+ \*/ = \{{\n",
        text,
        re.MULTILINE,
    )
    if not m:
        return None
    i = m.start()
    # Opening brace for this group (not m.end()-1, which is the newline after `{`).
    j = text.find("{", m.start(), m.end())
    if j < 0:
        return None
    depth = 0
    k = j
    while k < len(text):
        if text[k] == "{":
            depth += 1
        elif text[k] == "}":
            depth -= 1
            if depth == 0:
                end = text.find("\n", k) + 1
                return text[i:end]
        k += 1
    return None


def main() -> int:
    try:
        sig = git_signal_pbx()
    except subprocess.CalledProcessError as e:
        print("Could not read Signal.xcodeproj from git:", e, file=sys.stderr)
        return 1

    hcp = HCP_PBX.read_text()
    account_backup = extract_group_block(hcp, ACCOUNT_GID)
    if not account_backup:
        print("HCP Account group not found", file=sys.stderr)
        return 1

    gids = collect_ssk_group_ids(sig)
    end_marker = "/* End PBXGroup section */"
    if end_marker not in hcp:
        print("End PBXGroup marker missing", file=sys.stderr)
        return 1

    replaced = 0
    to_insert: list[str] = []
    for gid in gids:
        if gid == ACCOUNT_GID:
            continue
        newb = extract_group_block(sig, gid)
        if not newb:
            continue
        oldb = extract_group_block(hcp, gid)
        if oldb:
            if oldb != newb:
                hcp = hcp.replace(oldb, newb, 1)
                replaced += 1
        else:
            to_insert.append(newb)

    if to_insert:
        hcp = hcp.replace(end_marker, "".join(to_insert) + end_marker, 1)
    inserted = len(to_insert)

    acc_new = extract_group_block(hcp, ACCOUNT_GID)
    if acc_new and account_backup != acc_new:
        hcp = hcp.replace(acc_new, account_backup, 1)

    notif = extract_group_block(hcp, NOTIFICATIONS_GID)
    if notif and "children = (" in notif:
        insert = ""
        for ref in HCP_NOTIFICATIONS_EXTRA_REFS:
            if ref not in notif:
                insert += f"\t\t\t\t{ref} /* HCP notification source */,\n"
        if insert:
            notif_merged = notif.replace("children = (\n", "children = (\n" + insert, 1)
            hcp = hcp.replace(notif, notif_merged, 1)

    # LinkPreviewManager: SSK target must use same fileRef as upstream (6600BB19).
    hcp = hcp.replace(
        "\t\t\t\t6600BB172BA3A04C0005A035 /* LinkPreviewManager.swift */,\n",
        "\t\t\t\t6600BB192BA3A0930005A035 /* LinkPreviewManager.swift */,\n",
        1,
    )

    HCP_PBX.write_text(hcp)
    print(f"sync_ssk_groups: replaced {replaced} groups, inserted {inserted}; Account preserved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
