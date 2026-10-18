#!/usr/bin/env python3
"""Generate the offline keyboard catalog from Unicode Emoji 16.0.

Source: https://www.unicode.org/Public/emoji/16.0/emoji-test.txt
Unicode 16.0 is supported by the iOS 26 deployment baseline. This is Unicode
character/name data, not vendor artwork. UIKit renders the system emoji font.
The source data is © 2024 Unicode, Inc., distributed under Unicode License V3.
The complete notice is bundled in SnipKeyboard/Resources/emoji-unicode-license.txt
and embedded in the output. Source bytes are SHA-256 pinned below.

Run: python3 scripts/generate_emoji_catalog.py [--source /path/emoji-test.txt]
No timestamps or host-dependent ordering are included; identical source bytes
produce identical binary-plist bytes. Only fully-qualified RGI sequences are
included. Skin-tone relationships use Unicode names, not scalar removal, because
mixed-tone handshake/couple sequences can differ structurally from their base.
"""

import argparse
import hashlib
from pathlib import Path
import plistlib
import re
import unicodedata
import urllib.request

SOURCE_URL = "https://www.unicode.org/Public/emoji/16.0/emoji-test.txt"
SOURCE_SHA256 = "24f0c534e86cf142e2496953e8f0e46a3e702392911eddcd29c6cced85139697"
ROOT = Path(__file__).resolve().parent.parent
OUTPUT = ROOT / "SnipKeyboard/Resources/emoji-en.plist"
LICENSE = ROOT / "SnipKeyboard/Resources/emoji-unicode-license.txt"
TONE = re.compile(r"(?:medium-light|medium-dark|light|medium|dark) skin tone")
ROW = re.compile(r"^([0-9A-F ]+)\s*; fully-qualified\s*#\s*\S+\s+E[0-9.]+\s+(.+)$")
SYMBOLS = {
    "Smileys & Emotion": "face.smiling",
    "People & Body": "hand.wave",
    "Animals & Nature": "leaf",
    "Food & Drink": "fork.knife",
    "Travel & Places": "car",
    "Activities": "sportscourt",
    "Objects": "lightbulb",
    "Symbols": "heart",
    "Flags": "flag",
}
# Small authored English aliases complement the public Unicode names/subgroups.
ALIASES = {
    "grinning": "happy smile",
    "smiling": "happy smile",
    "laughing": "lol laugh funny",
    "tears of joy": "lol laugh funny",
    "crying": "sad cry tears",
    "sobbing": "sad cry tears",
    "frowning": "sad unhappy",
    "heart": "love",
    "thumbs up": "yes like approve good thumbsup",
    "thumbs down": "no dislike disapprove thumbsdown",
    "folded hands": "pray please thanks thank you",
    "party": "celebrate celebration",
    "partying": "celebrate celebration",
    "check mark": "yes done correct tick",
    "cross mark": "no wrong cancel",
    "collision": "boom explosion",
    "pile of poo": "poop",
    "mobile phone": "cellphone smartphone",
    "face with tears": "cry",
    "red heart": "heart love",
    "united states": "usa america us",
    "united kingdom": "uk britain british",
}


def normalize(text: str) -> str:
    folded = unicodedata.normalize("NFKD", text.casefold())
    return " ".join(re.sub(r"[^a-z0-9]+", " ", folded).split())


def base_name(name: str) -> str:
    prefix, separator, suffix = name.partition(": ")
    if not separator:
        return name
    qualifiers = [part for part in suffix.split(", ") if not TONE.fullmatch(part)]
    # Unicode's mixed-tone gender-neutral couples spell out both people, while
    # the unmodified legacy scalar is named simply "kiss" / "couple with heart".
    if prefix in ("kiss", "couple with heart") and qualifiers == ["person", "person"]:
        qualifiers = []
    return prefix + (": " + ", ".join(qualifiers) if qualifiers else "")


def generate(source: bytes, license_text: str) -> bytes:
    digest = hashlib.sha256(source).hexdigest()
    if digest != SOURCE_SHA256:
        raise ValueError(f"Unexpected Unicode source SHA-256: {digest}")
    groups = []
    entries = []
    subgroup = ""
    group_index = -1
    for line in source.decode("utf-8").splitlines():
        if line.startswith("# group: "):
            name = line.removeprefix("# group: ")
            if name == "Component":
                group_index = -1
                continue
            group_index = len(groups)
            groups.append({"n": name, "s": SYMBOLS[name], "e": []})
        elif line.startswith("# subgroup: "):
            subgroup = line.removeprefix("# subgroup: ")
        elif match := ROW.match(line):
            if group_index < 0:
                raise ValueError("Fully qualified emoji outside a display group")
            text = "".join(chr(int(value, 16)) for value in match[1].split())
            name = match[2]
            aliases = " ".join(value for key, value in ALIASES.items() if key in name)
            entries.append({"t": text, "n": name, "g": group_index, "b": -1,
                            "v": [], "k": normalize(name + " " + subgroup + " " + aliases)})
    by_name = {entry["n"]: index for index, entry in enumerate(entries)}
    if len(by_name) != len(entries):
        raise ValueError("Duplicate Unicode names")
    for index, entry in enumerate(entries):
        name = base_name(entry["n"])
        if name not in by_name:
            raise ValueError(f"Missing unmodified base for {entry['n']}")
        base = by_name[name]
        entry["b"] = base
        if base == index:
            groups[entry["g"]]["e"].append(index)
        else:
            entries[base]["v"].append(index)
    if len(entries) != 3781 or len(groups) != 9:
        raise ValueError(f"Unexpected Emoji 16.0 inventory: {len(entries)} entries, {len(groups)} groups")
    catalog = {"version": "16.0", "source": SOURCE_URL, "sha256": digest,
               "license": license_text, "groups": groups, "entries": entries}
    return plistlib.dumps(catalog, fmt=plistlib.FMT_BINARY, sort_keys=True)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, help="Use a local, hash-verified Unicode source")
    parser.add_argument("--output", type=Path, default=OUTPUT)
    arguments = parser.parse_args()
    if arguments.source:
        source = arguments.source.read_bytes()
    else:
        with urllib.request.urlopen(SOURCE_URL, timeout=30) as response:
            source = response.read()
    payload = generate(source, LICENSE.read_text(encoding="utf-8"))
    arguments.output.write_bytes(payload)
    print(f"Wrote {arguments.output}: {len(payload)} bytes, SHA-256 {hashlib.sha256(payload).hexdigest()}")


if __name__ == "__main__":
    main()
