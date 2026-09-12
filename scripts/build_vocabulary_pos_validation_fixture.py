#!/usr/bin/env python3
"""Build the frozen UD 2.18 development/held-out POS validation sample."""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from collections import Counter, defaultdict
from pathlib import Path


SOURCES = {
    "en_ewt_dev": {
        "repository": "https://github.com/UniversalDependencies/UD_English-EWT",
        "revision": "b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c",
        "tag": "r2.18",
        "path": "en_ewt-ud-dev.conllu",
        "sha256": "39239e0a60db3ae68f4b7036189f11b6692741d10ff8240dd91f74f2760d90f8",
        "license": "CC BY-SA 4.0",
        "language": "en",
        "evaluationSplit": "development",
    },
    "en_ewt_test": {
        "repository": "https://github.com/UniversalDependencies/UD_English-EWT",
        "revision": "b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c",
        "tag": "r2.18",
        "path": "en_ewt-ud-test.conllu",
        "sha256": "fa024f43dc5da3c5ac02563bc9bd0e974f46cbb1560823976a8f342a37dc494a",
        "license": "CC BY-SA 4.0",
        "language": "en",
        "evaluationSplit": "heldout",
    },
    "de_gsd_dev": {
        "repository": "https://github.com/UniversalDependencies/UD_German-GSD",
        "revision": "81d8c3612a88f5867fd089e9c0a5466ef230078b",
        "tag": "r2.18",
        "path": "de_gsd-ud-dev.conllu",
        "sha256": "01e8e674973592747ffe9a8c77fcf9d2f5936a8484e731ad4f76254318a8952c",
        "license": "Annotations CC BY-SA 4.0; underlying-text terms in upstream LICENSE.txt",
        "language": "de",
        "evaluationSplit": "development",
    },
    "de_gsd_test": {
        "repository": "https://github.com/UniversalDependencies/UD_German-GSD",
        "revision": "81d8c3612a88f5867fd089e9c0a5466ef230078b",
        "tag": "r2.18",
        "path": "de_gsd-ud-test.conllu",
        "sha256": "595070aa50b706a91dc66f17c296f7a9a25cbc75269f177c27680fb1c21528ab",
        "license": "Annotations CC BY-SA 4.0; underlying-text terms in upstream LICENSE.txt",
        "language": "de",
        "evaluationSplit": "heldout",
    },
}

TARGETS = {"development": 80, "heldout": 160}
ELIGIBLE_UPOS = {"NOUN", "PROPN", "VERB", "AUX", "ADJ", "ADV", "PRON", "DET", "ADP", "CCONJ", "SCONJ", "INTJ", "PART"}


def download(source: dict) -> bytes:
    url = f"{source['repository'].replace('github.com', 'raw.githubusercontent.com')}/{source['tag']}/{source['path']}"
    data = urllib.request.urlopen(url, timeout=30).read()
    if hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"checksum mismatch for {source['path']}")
    return data


def genre(source_id: str, sentence_id: str) -> str:
    if source_id.startswith("de_gsd"):
        return "gsd-mixed-web"
    prefix = sentence_id.split("-", 1)[0]
    return prefix if prefix in {"answers", "email", "newsgroup", "reviews", "weblog"} else "ewt-other"


def cases(source_id: str, source: dict, data: bytes) -> list[dict]:
    values = []
    for block in data.decode("utf-8").strip().split("\n\n"):
        lines = block.splitlines()
        sentence_id = next((line.split(" = ", 1)[1] for line in lines if line.startswith("# sent_id = ")), None)
        text = next((line.split(" = ", 1)[1] for line in lines if line.startswith("# text = ")), None)
        if not sentence_id or text is None:
            continue
        tokens = []
        for line in lines:
            if line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) == 10 and columns[0].isdigit() and columns[3] in ELIGIBLE_UPOS:
                tokens.append(columns)
        surface_counts = Counter(token[1].casefold() for token in tokens)
        for token in tokens:
            if surface_counts[token[1].casefold()] != 1 or not any(character.isalpha() for character in token[1]):
                continue
            case_id = f"{source_id}:{sentence_id}:{token[0]}"
            values.append({
                "caseID": case_id,
                "sourceID": source_id,
                "sourceSentenceID": sentence_id,
                "languageCode": source["language"],
                "evaluationSplit": source["evaluationSplit"],
                "genre": genre(source_id, sentence_id),
                "text": text,
                "tokenID": token[0],
                "surface": token[1],
                "goldLemma": token[2],
                "goldUPOS": token[3],
                "goldXPOS": token[4],
                "goldFeatures": token[5],
                "isParticiple": "VerbForm=Part" in token[5],
                "occurrenceWeight": 1,
                "selectionHash": hashlib.sha256(case_id.encode()).hexdigest(),
            })
    return values


def select(values: list[dict], target: int) -> list[dict]:
    by_stratum = defaultdict(list)
    for value in values:
        key = (value["genre"], value["goldUPOS"], value["isParticiple"])
        by_stratum[key].append(value)
    for rows in by_stratum.values():
        rows.sort(key=lambda row: (row["selectionHash"], row["caseID"]))

    selected = []
    used_sentences = set()
    while len(selected) < target:
        progressed = False
        for key in sorted(by_stratum):
            rows = by_stratum[key]
            while rows and (rows[0]["sourceID"], rows[0]["sourceSentenceID"]) in used_sentences:
                rows.pop(0)
            if not rows:
                continue
            row = rows.pop(0)
            used_sentences.add((row["sourceID"], row["sourceSentenceID"]))
            selected.append(row)
            progressed = True
            if len(selected) == target:
                break
        if not progressed:
            raise ValueError(f"not enough unique sentences for target {target}")
    return sorted(selected, key=lambda row: (row["languageCode"], row["evaluationSplit"], row["selectionHash"]))


def support(selected: list[dict]) -> dict:
    def counts(field: str) -> dict[str, int]:
        return dict(sorted(Counter(row[field] for row in selected).items()))
    return {
        "cases": len(selected),
        "uniqueSentences": len({(row["sourceID"], row["sourceSentenceID"]) for row in selected}),
        "byLanguage": counts("languageCode"),
        "bySplit": counts("evaluationSplit"),
        "byGenre": counts("genre"),
        "byUPOS": counts("goldUPOS"),
        "participlesByLanguageAndSplit": dict(sorted(Counter(
            f"{row['languageCode']}:{row['evaluationSplit']}" for row in selected if row["isParticiple"]
        ).items())),
    }


def build() -> dict:
    all_cases = []
    for source_id, source in SOURCES.items():
        all_cases.extend(cases(source_id, source, download(source)))
    selected = []
    for language in ("en", "de"):
        for split, target in TARGETS.items():
            selected.extend(select([
                row for row in all_cases
                if row["languageCode"] == language and row["evaluationSplit"] == split
            ], target))
    for row in selected:
        row.pop("selectionHash")
    selected.sort(key=lambda row: row["caseID"])
    return {
        "schemaVersion": 1,
        "fixtureID": "ud-v2.18-pos-validation-v1",
        "release": "UD 2.18",
        "dataRole": "development-and-heldout",
        "heldoutStatus": "frozenNotScored",
        "selectionPolicy": {
            "version": "unique-sentence-stratified-sha256-v1",
            "targetsPerLanguage": TARGETS,
            "strata": ["declared genre/source", "UPOS", "VerbForm=Part"],
            "withinStratumOrder": "SHA256(caseID), then caseID",
            "oneSelectedTokenPerSentence": True,
            "productionThresholdsTunedFromFixture": False,
        },
        "sources": SOURCES,
        "support": support(selected),
        "cases": selected,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(build(), indent=2, sort_keys=True, ensure_ascii=False) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
