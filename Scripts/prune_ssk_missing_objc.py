#!/usr/bin/env python3
"""Remove SignalServiceKit target references to .m/.h files that are not on disk."""

from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PBX = REPO / "HCP.xcodeproj/project.pbxproj"
SSK_SOURCES = "F9C5C893289451B900548EEE"
SSK_TESTS_SOURCES = "F9C5C89A289451B900548EEE"
SSK_HEADERS = "F9C5C892289451B900548EEE"


def strip_path(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] == '"':
        s = s[1:-1].replace('\\"', '"')
    return s


def main() -> None:
    text = PBX.read_text(encoding="utf-8")
    file_refs: dict[str, tuple[str, str]] = {}  # id -> (path, full line)
    for line in text.splitlines():
        if "isa = PBXFileReference" not in line:
            continue
        m = re.match(r"^\t\t([A-F0-9]{24}) /\* ([^*]+) \*/ = \{isa = PBXFileReference;", line)
        if not m:
            continue
        uid, name = m.group(1), m.group(2)
        pm = re.search(r"path = ([^;]+);", line)
        if not pm:
            continue
        path = strip_path(pm.group(1))
        if not (name.endswith(".m") or name.endswith(".h")):
            continue
        file_refs[uid] = (path, line)

    ssk_root = REPO / "SignalServiceKit"

    def resolves(path: str) -> Path | None:
        if path.startswith("SignalServiceKit/"):
            p = REPO / path
            return p if p.is_file() else None
        p = ssk_root / path
        if p.is_file():
            return p
        bn = Path(path).name
        matches = [x for x in ssk_root.rglob(bn) if x.is_file()]
        if len(matches) == 1:
            return matches[0]
        return None

    missing_ids: set[str] = set()
    for uid, (path, _) in file_refs.items():
        if resolves(path) is None:
            missing_ids.add(uid)

    if not missing_ids:
        print("No missing SSK .h/.m file refs found")
        return

    build_to_ref: dict[str, str] = {}
    for line in text.splitlines():
        for phase in ("Sources", "Headers"):
            m = re.match(
                rf"^\t\t([A-F0-9]{{24}}) /\* .+ in {phase} \*/ = \{{isa = PBXBuildFile; fileRef = ([A-F0-9]{{24}})",
                line,
            )
            if m:
                build_to_ref[m.group(1)] = m.group(2)

    # Phases to prune (SSK only)
    def phase_build_ids(phase_id: str) -> set[str]:
        marker = f"\t\t{phase_id} /* "
        idx = text.find(marker)
        if idx < 0:
            return set()
        sub = text[idx:]
        if "isa = PBXSourcesBuildPhase" in sub[:200]:
            pass
        elif "isa = PBXHeadersBuildPhase" in sub[:200]:
            pass
        fs = sub.find("\t\t\tfiles = (") + len("\t\t\tfiles = (")
        fe = sub.find("\t\t\t);", fs)
        block = sub[fs:fe]
        out = set()
        for line in block.splitlines():
            m = re.match(r"\t\t\t\t([A-F0-9]{24}) /\*", line)
            if m:
                out.add(m.group(1))
        return out

    ssk_src_builds = phase_build_ids(SSK_SOURCES)
    ssk_hdr_builds = phase_build_ids(SSK_HEADERS)

    remove_build: set[str] = set()
    for bid, rid in build_to_ref.items():
        if rid not in missing_ids:
            continue
        if bid in ssk_src_builds or bid in ssk_hdr_builds:
            remove_build.add(bid)

    remove_ref = set(missing_ids)

    lines_out: list[str] = []
    for line in text.splitlines():
        m = re.match(
            r"^\t\t([A-F0-9]{24}) /\* ([^*]+) \*/ = \{isa = PBX(FileReference|BuildFile);",
            line,
        )
        if m and m.group(1) in remove_ref and "isa = PBXFileReference" in line:
            continue
        if m and m.group(1) in remove_build and "isa = PBXBuildFile" in line:
            continue
        if re.match(r"\t\t\t\t([A-F0-9]{24}) /\*", line):
            uid = re.match(r"\t\t\t\t([A-F0-9]{24}) /\*", line).group(1)
            if uid in remove_build or uid in remove_ref:
                continue
        lines_out.append(line)

    PBX.write_text("\n".join(lines_out) + "\n", encoding="utf-8")
    print(
        f"Pruned {len(remove_ref)} missing file refs and {len(remove_build)} SSK build file entries",
        file=sys.stderr,
    )


if __name__ == "__main__":
    main()
