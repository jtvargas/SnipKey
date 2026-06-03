#!/usr/bin/env python3
"""
Add Swift source files from SnipKeyboard/QWERTY/V2/ to the Xcode project.

Adds:
  - A PBXFileReference for each .swift file
  - The file to the existing QWERTY PBXGroup (so it shows up in the Xcode navigator)
  - PBXBuildFile entries for both target Sources phases (SnipKeyboard extension + SnipKey app)
  - Entries in both PBXSourcesBuildPhase blocks

Idempotent: re-running skips files that are already present.

Usage:  python3 scripts/add_v2_files.py
"""

import os
import re
import sys
import hashlib

PROJ = os.path.join(os.path.dirname(__file__), "..", "SnipKey.xcodeproj", "project.pbxproj")
V2_DIR = os.path.join(os.path.dirname(__file__), "..", "SnipKeyboard", "QWERTY", "V2")

QWERTY_GROUP_ID = "06AA100F2F30A00100B1C000"
# Two SourcesBuildPhase block IDs, matching what's in project.pbxproj:
SNIPKEYBOARD_SOURCES_ID = "066E69D02BB9831900D971E8"   # SnipKeyboard extension target
SNIPKEY_SOURCES_ID = "066FAF062BB216160086F135"        # SnipKey app target


def stable_id(seed: str) -> str:
    """Deterministic 24-hex-char ID (Xcode-style). Same input -> same ID."""
    return hashlib.sha1(seed.encode()).hexdigest()[:24].upper()


def list_v2_files() -> list[str]:
    if not os.path.isdir(V2_DIR):
        return []
    return sorted(f for f in os.listdir(V2_DIR) if f.endswith(".swift"))


def main() -> int:
    with open(PROJ, "r") as f:
        content = f.read()

    files = list_v2_files()
    if not files:
        print("No .swift files in V2/")
        return 0

    new_buildfile_lines: list[str] = []
    new_fileref_lines: list[str] = []
    new_group_children: list[str] = []
    new_snipkeyboard_sources: list[str] = []
    new_snipkey_sources: list[str] = []
    added: list[str] = []

    for fname in files:
        # Skip if already in project
        if f"V2/{fname}" in content or f"path = V2/{fname}" in content or f"/* {fname} */" in content:
            # Crude check — accept either path form or any reference to the bare name
            # in the right context. The "V2/" form is the unique marker we use.
            # If the bare filename is already referenced (unlikely collision), skip too.
            print(f"Skipping {fname} — already referenced in project")
            continue

        fileref_id = stable_id(f"fileref:V2/{fname}")
        group_child_id = fileref_id  # PBXGroup children list reuses the fileref ID
        snipkeyboard_buildfile_id = stable_id(f"buildfile:snipkeyboard:V2/{fname}")
        snipkey_buildfile_id = stable_id(f"buildfile:snipkey:V2/{fname}")

        # 1. PBXBuildFile entries (one per target)
        new_buildfile_lines.append(
            f"\t\t{snipkeyboard_buildfile_id} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref_id} /* {fname} */; }};"
        )
        new_buildfile_lines.append(
            f"\t\t{snipkey_buildfile_id} /* {fname} in Sources */ = {{isa = PBXBuildFile; fileRef = {fileref_id} /* {fname} */; }};"
        )

        # 2. PBXFileReference entry
        new_fileref_lines.append(
            f"\t\t{fileref_id} /* {fname} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; name = {fname}; path = V2/{fname}; sourceTree = \"<group>\"; }};"
        )

        # 3. QWERTY group child entry
        new_group_children.append(f"\t\t\t\t{group_child_id} /* {fname} */,")

        # 4. Source build phase entries
        new_snipkeyboard_sources.append(f"\t\t\t\t{snipkeyboard_buildfile_id} /* {fname} in Sources */,")
        new_snipkey_sources.append(f"\t\t\t\t{snipkey_buildfile_id} /* {fname} in Sources */,")

        added.append(fname)

    if not added:
        print("All V2 files already in project.")
        return 0

    # --- Inject into project.pbxproj ---

    # PBXBuildFile section: insert before "/* End PBXBuildFile section */"
    content = content.replace(
        "/* End PBXBuildFile section */",
        "\n".join(new_buildfile_lines) + "\n/* End PBXBuildFile section */",
    )

    # PBXFileReference section: insert before "/* End PBXFileReference section */"
    content = content.replace(
        "/* End PBXFileReference section */",
        "\n".join(new_fileref_lines) + "\n/* End PBXFileReference section */",
    )

    # QWERTY group children: insert just before the closing ");" of the children list.
    # Find the QWERTY group block.
    group_pattern = re.compile(
        rf"({re.escape(QWERTY_GROUP_ID)} /\* QWERTY \*/ = {{\s*isa = PBXGroup;\s*children = \()([\s\S]*?)(\s*\);)",
        re.MULTILINE,
    )
    def group_repl(m: re.Match) -> str:
        return m.group(1) + m.group(2) + "\n" + "\n".join(new_group_children) + m.group(3)
    new_content, n = group_pattern.subn(group_repl, content)
    if n != 1:
        print(f"ERROR: Could not find QWERTY PBXGroup block (matched {n} times)")
        return 1
    content = new_content

    # Source build phases: inject into the SnipKeyboard target's Sources block
    sb_pattern = re.compile(
        rf"({re.escape(SNIPKEYBOARD_SOURCES_ID)} /\* Sources \*/ = {{\s*isa = PBXSourcesBuildPhase;[\s\S]*?files = \()([\s\S]*?)(\s*\);)",
        re.MULTILINE,
    )
    def sb_repl(m: re.Match) -> str:
        return m.group(1) + m.group(2) + "\n" + "\n".join(new_snipkeyboard_sources) + m.group(3)
    new_content, n = sb_pattern.subn(sb_repl, content)
    if n != 1:
        print(f"ERROR: Could not find SnipKeyboard Sources block (matched {n} times)")
        return 1
    content = new_content

    sk_pattern = re.compile(
        rf"({re.escape(SNIPKEY_SOURCES_ID)} /\* Sources \*/ = {{\s*isa = PBXSourcesBuildPhase;[\s\S]*?files = \()([\s\S]*?)(\s*\);)",
        re.MULTILINE,
    )
    def sk_repl(m: re.Match) -> str:
        return m.group(1) + m.group(2) + "\n" + "\n".join(new_snipkey_sources) + m.group(3)
    new_content, n = sk_pattern.subn(sk_repl, content)
    if n != 1:
        print(f"ERROR: Could not find SnipKey Sources block (matched {n} times)")
        return 1
    content = new_content

    with open(PROJ, "w") as f:
        f.write(content)

    print(f"Added {len(added)} file(s) to project.pbxproj:")
    for fname in added:
        print(f"  + V2/{fname}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
