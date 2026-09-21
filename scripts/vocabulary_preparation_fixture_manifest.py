#!/usr/bin/env python3
import json
import os
import sys
from pathlib import Path


EXPECTED = {(language, format_name) for language in ("en", "de") for format_name in ("pdf", "epub", "docx")}


def load(path: Path) -> dict:
    data = json.loads(path.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1:
        raise ValueError("schema_version must be 1")
    fixtures = data.get("fixtures")
    if not isinstance(fixtures, list):
        raise ValueError("fixtures must be an array")
    combinations = {(item.get("language"), item.get("format")) for item in fixtures}
    if combinations != EXPECTED or len(fixtures) != 6:
        raise ValueError("fixtures must contain exactly English/German PDF, EPUB, and DOCX entries")
    aliases = set()
    for item in fixtures:
        alias = item.get("alias", "")
        fixture_path = item.get("path", "")
        if not alias or not all(character.islower() or character.isdigit() or character == "-" for character in alias):
            raise ValueError("aliases must use lowercase letters, digits, and hyphens")
        if alias in aliases:
            raise ValueError("fixture aliases must be unique")
        aliases.add(alias)
        if not os.path.isabs(fixture_path) or not os.path.isfile(fixture_path):
            raise ValueError(f"fixture {alias} must be an absolute readable file")
        if Path(fixture_path).suffix.lower() != f".{item['format']}":
            raise ValueError(f"fixture {alias} extension does not match its format")
    return data


def main() -> int:
    if len(sys.argv) != 3 or sys.argv[1] not in ("validate", "paths"):
        print("usage: vocabulary_preparation_fixture_manifest.py validate|paths <manifest>", file=sys.stderr)
        return 2
    try:
        manifest = load(Path(sys.argv[2]))
    except (OSError, json.JSONDecodeError, ValueError) as error:
        print(f"invalid vocabulary preparation fixture manifest: {error}", file=sys.stderr)
        return 2
    if sys.argv[1] == "paths":
        for item in manifest["fixtures"]:
            print(item["path"])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
