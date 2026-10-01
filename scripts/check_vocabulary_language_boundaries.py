#!/usr/bin/env python3
from __future__ import annotations

import pathlib
import re
import sys


ROOT = pathlib.Path(__file__).resolve().parents[1]
CORE_VOCABULARY = ROOT / "Sources" / "LeafReaderCore" / "VocabularyReview"
VALIDATION_VOCABULARY = ROOT / "Sources" / "LeafReaderValidation" / "Vocabulary"
VOCABULARY_ROOTS = [
    CORE_VOCABULARY,
    ROOT / "Sources" / "LeafReaderApp" / "VocabularyReview",
    VALIDATION_VOCABULARY,
]


def swift_files(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(root.rglob("*.swift"))


def relative(path: pathlib.Path) -> str:
    return str(path.relative_to(ROOT))


def fail(message: str, offenders: list[tuple[pathlib.Path, str]]) -> None:
    print(f"vocabulary language boundaries: FAILED - {message}", file=sys.stderr)
    for path, detail in offenders:
        print(f"  {relative(path)}: {detail}", file=sys.stderr)
    raise SystemExit(1)


apple_nlp = re.compile(r"\b(?:NLLanguage|NLTagger|NLLanguageRecognizer|NLTag)\b|^import NaturalLanguage$", re.MULTILINE)
core_offenders: list[tuple[pathlib.Path, str]] = []
for path in swift_files(CORE_VOCABULARY):
    text = path.read_text(encoding="utf-8")
    match = apple_nlp.search(text)
    if match:
        core_offenders.append((path, f"Apple NaturalLanguage token `{match.group(0)}` crossed the Core vocabulary boundary"))
if core_offenders:
    fail("Apple NaturalLanguage must stay behind LeafReaderApp vocabulary adapters", core_offenders)


implicit_english_default = re.compile(
    r"\blanguage(?:ID)?\s*:\s*[A-Za-z0-9_.?<>,\[\] ]+?\s*=\s*\.english\b",
    re.MULTILINE,
)
fallback_english = re.compile(r"\?\?\s*(?:VocabularyLanguageID\.)?english\b")
conditional_english_fallback = re.compile(
    r"\?\s*(?:VocabularyLanguageID\.)?[A-Za-z][A-Za-z0-9_]*\s*:\s*(?:VocabularyLanguageID\.)?english\b"
)
canonical_key_language_guess = re.compile(
    r"hasPrefix\(\s*\"de\\\|\"\s*\)\s*\?\s*\"de\"\s*:\s*\"en\""
)
default_offenders: list[tuple[pathlib.Path, str]] = []
for root in VOCABULARY_ROOTS:
    for path in swift_files(root):
        text = path.read_text(encoding="utf-8")
        if match := implicit_english_default.search(text):
            default_offenders.append((path, f"implicit English language default `{match.group(0).strip()}`"))
        if match := fallback_english.search(text):
            default_offenders.append((path, f"implicit English nil fallback `{match.group(0)}`"))
        if match := conditional_english_fallback.search(text):
            default_offenders.append((path, f"implicit English conditional fallback `{match.group(0)}`"))
        if match := canonical_key_language_guess.search(text):
            default_offenders.append((path, f"language inferred from canonical-key prefix `{match.group(0)}`"))
if default_offenders:
    fail("language-sensitive vocabulary routing must require identity explicitly", default_offenders)


legacy_name_offenders: list[tuple[pathlib.Path, str]] = []
for root in VOCABULARY_ROOTS:
    for path in swift_files(root):
        if "isSingleEnglishWord" in path.read_text(encoding="utf-8"):
            legacy_name_offenders.append((path, "use language-neutral `isSingleVocabularyWord`"))
if legacy_name_offenders:
    fail("the Unicode token boundary must not be named as English-only", legacy_name_offenders)


print("vocabulary language boundaries: ok - explicit identity, provider-neutral Core, language-neutral token naming")
