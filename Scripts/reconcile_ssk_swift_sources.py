#!/usr/bin/env python3
"""Add SignalServiceKit Swift files missing from the SignalServiceKit target Sources phase."""

from __future__ import annotations

import re
import uuid
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PBX = REPO / "HCP.xcodeproj/project.pbxproj"
SSK_SOURCES_PHASE_ID = "F9C5C893289451B900548EEE"
SSK_TESTS_SOURCES_PHASE_ID = "F9C5C89A289451B900548EEE"
SSK_MAIN_GROUP_ID = "F9C5C898289451B900548EEE"


def gen_id() -> str:
    return uuid.uuid4().hex[:24].upper()


def strip_path_value(s: str) -> str:
    s = s.strip()
    if len(s) >= 2 and s[0] == s[-1] == '"':
        s = s[1:-1].replace('\\"', '"')
    return s


def pbx_quote_path(p: str) -> str:
    if re.search(r'[\s+"]', p):
        return '"' + p.replace("\\", "\\\\").replace('"', '\\"') + '"'
    return p


def main() -> None:
    text = PBX.read_text(encoding="utf-8")

    file_refs: dict[str, str] = {}
    for line in text.splitlines():
        if "isa = PBXFileReference" not in line or "sourcecode.swift" not in line:
            continue
        m = re.match(
            r"^\t\t([A-F0-9]{24}) /\* ([^*]+) \*/ = \{isa = PBXFileReference;",
            line,
        )
        if not m:
            continue
        uid = m.group(1)
        pm = re.search(r"path = ([^;]+);", line)
        if not pm:
            continue
        file_refs[uid] = strip_path_value(pm.group(1))

    build_to_ref: dict[str, str] = {}
    for line in text.splitlines():
        m = re.match(
            r"^\t\t([A-F0-9]{24}) /\* .+ in Sources \*/ = \{isa = PBXBuildFile; fileRef = ([A-F0-9]{24})",
            line,
        )
        if m:
            build_to_ref[m.group(1)] = m.group(2)

    marker = f"\t\t{SSK_SOURCES_PHASE_ID} /* Sources */ = {{\n\t\t\tisa = PBXSourcesBuildPhase;"
    idx = text.find(marker)
    if idx < 0:
        raise SystemExit("SignalServiceKit Sources phase not found")
    sub = text[idx:]
    fs = sub.find("\t\t\tfiles = (") + len("\t\t\tfiles = (")
    fe = sub.find("\t\t\t);", fs)
    files_block = sub[fs:fe]

    phase_build_ids: set[str] = set()
    for line in files_block.splitlines():
        m = re.match(r"\t\t\t\t([A-F0-9]{24}) /\*", line)
        if m:
            phase_build_ids.add(m.group(1))

    ssk_root = REPO / "SignalServiceKit"

    def resolve_ref_path(p: str) -> Path | None:
        if p.startswith("SignalServiceKit/"):
            cand = REPO / p
            return cand if cand.is_file() else None
        cand = ssk_root / p
        if cand.is_file():
            return cand
        bn = Path(p).name
        matches = [
            x
            for x in ssk_root.rglob(bn)
            if x.is_file() and x.suffix == ".swift" and "/tests/" not in str(x).replace("\\", "/")
        ]
        if len(matches) == 1:
            return matches[0]
        return None

    compiled: set[Path] = set()
    for bid in phase_build_ids:
        rid = build_to_ref.get(bid)
        if not rid:
            continue
        p = file_refs.get(rid)
        if not p:
            continue
        resolved = resolve_ref_path(p)
        if resolved:
            compiled.add(resolved.resolve())

    def is_test_named(path: Path) -> bool:
        n = path.name
        return n.endswith("Test.swift") or n.endswith("Tests.swift")

    disk_swift = [
        f.resolve()
        for f in ssk_root.rglob("*.swift")
        if f.is_file()
        and "/tests/" not in str(f).replace("\\", "/")
        and not is_test_named(f)
    ]
    missing = sorted(set(disk_swift) - compiled, key=lambda x: x.as_posix())
    print(f"SSK Swift on disk: {len(disk_swift)}; in target: {len(compiled)}; missing: {len(missing)}")
    if not missing:
        return

    new_lines_build: list[str] = []
    new_lines_fileref: list[str] = []
    new_group_children: list[str] = []
    new_phase_lines: list[str] = []

    for f in missing:
        # Paths are relative to the SignalServiceKit group folder (path = SignalServiceKit).
        rel = f.relative_to(ssk_root).as_posix()
        name = f.name
        fr = gen_id()
        bf = gen_id()
        qp = pbx_quote_path(rel)
        new_lines_fileref.append(
            f"\t\t{fr} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; "
            f"lastKnownFileType = sourcecode.swift; path = {qp}; sourceTree = \"<group>\"; }};"
        )
        new_lines_build.append(
            f"\t\t{bf} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {fr} /* {name} */; }};"
        )
        new_group_children.append(f"\t\t\t\t{fr} /* {name} */,")
        new_phase_lines.append(f"\t\t\t\t{bf} /* {name} in Sources */,")

    anchor_build = (
        "\t\tD90AA6192CC961ED00021CB0 /* BackupArchiveIntegrationTests.swift in Sources */"
    )
    if anchor_build not in text:
        anchor_build = "\t\tD90D4D842BBB61680097C573 /* BackupArchive+EmptyFrameId.swift in Sources */"
    if anchor_build not in text:
        raise SystemExit("anchor for PBXBuildFile not found")
    text = text.replace(anchor_build, "\n".join(new_lines_build) + "\n" + anchor_build, 1)

    anchor_ref = "\t\tD90D4C822BB633560097C573 /* Backup.proto */"
    if anchor_ref not in text:
        raise SystemExit("anchor for PBXFileReference not found")
    text = text.replace(anchor_ref, "\n".join(new_lines_fileref) + "\n" + anchor_ref, 1)

    grp_open = (
        f"\t\t{SSK_MAIN_GROUP_ID}289451B900548EEE /* SignalServiceKit */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n\t\t\tchildren = ("
    )
    # Fix typo: full group id is F9C5C898289451B900548EEE
    grp_open = (
        "\t\tF9C5C898289451B900548EEE /* SignalServiceKit */ = {\n"
        "\t\t\tisa = PBXGroup;\n\t\t\tchildren = ("
    )
    if grp_open not in text:
        raise SystemExit("SSK main group header not found")
    gid = gen_id()
    group_def = (
        f"\t\t{gid} /* _RecoveredSSKSwift */ = {{\n"
        f"\t\t\tisa = PBXGroup;\n"
        f"\t\t\tchildren = (\n"
        + "\n".join(new_group_children)
        + "\n"
        f"\t\t\t);\n"
        f"\t\t\tname = _RecoveredSSKSwift;\n"
        f'\t\t\tsourceTree = "<group>";\n'
        f"\t\t}};\n\n"
    )
    text = text.replace(
        grp_open,
        group_def + grp_open + f"\n\t\t\t\t{gid} /* _RecoveredSSKSwift */,",
        1,
    )

    src = f"\t\t{SSK_SOURCES_PHASE_ID} /* Sources */ = {{"
    next_src = f"\t\t{SSK_TESTS_SOURCES_PHASE_ID} /* Sources */ = {{"
    a = text.find(src)
    b = text.find(next_src, a + 1)
    if a < 0 or b < 0:
        raise SystemExit("SSK Sources / SSKTests Sources boundary not found")
    chunk = text[a:b]
    fi = chunk.find("\t\t\tfiles = (") + len("\t\t\tfiles = (")
    end = chunk.find("\t\t\t);", fi)
    new_chunk = chunk[:end] + "\n" + "\n".join(new_phase_lines) + "\n" + chunk[end:]
    text = text[:a] + new_chunk + text[b:]

    PBX.write_text(text, encoding="utf-8")
    print(f"Added {len(missing)} Swift files to SignalServiceKit target via {PBX}")


if __name__ == "__main__":
    main()
