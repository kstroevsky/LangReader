#!/usr/bin/env python3
"""Build the pinned UD 2.18 POS excerpt fixture."""

from __future__ import annotations

import argparse
import hashlib
import json
import urllib.request
from pathlib import Path

SOURCES = {
    "en_ewt": {
        "repository": "https://github.com/UniversalDependencies/UD_English-EWT",
        "revision": "b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c",
        "tag": "r2.18",
        "path": "en_ewt-ud-test.conllu",
        "sha256": "fa024f43dc5da3c5ac02563bc9bd0e974f46cbb1560823976a8f342a37dc494a",
        "license": "CC BY-SA 4.0",
        "language": "en",
    },
    "de_gsd": {
        "repository": "https://github.com/UniversalDependencies/UD_German-GSD",
        "revision": "81d8c3612a88f5867fd089e9c0a5466ef230078b",
        "tag": "r2.18",
        "path": "de_gsd-ud-test.conllu",
        "sha256": "595070aa50b706a91dc66f17c296f7a9a25cbc75269f177c27680fb1c21528ab",
        "license": "Annotations CC BY-SA 4.0; underlying-text terms in upstream LICENSE.txt",
        "language": "de",
    },
}

SELECTIONS = [
    ("en_ewt", "weblog-blogspot.com_floppingaces_20050313182621_ENG_20050313_182621-0011", "33", 30),
    ("en_ewt", "email-enronsent28_01-0013", "13", 25),
    ("en_ewt", "email-enronsent32_01-0032", "18", 40),
    ("en_ewt", "answers-20111108081911AAy6QeW_ans-0001", "23", 20),
    ("de_gsd", "test-s255", "5", 45),
    ("de_gsd", "test-s255", "30", 15),
    ("de_gsd", "test-s422", "6", 30),
    ("de_gsd", "test-s447", "19", 20),
]


def download(source: dict) -> bytes:
    url = f"{source['repository'].replace('github.com', 'raw.githubusercontent.com')}/{source['tag']}/{source['path']}"
    data = urllib.request.urlopen(url, timeout=30).read()
    if hashlib.sha256(data).hexdigest() != source["sha256"]:
        raise ValueError(f"checksum mismatch for {source['path']}")
    return data


def parse(data: bytes) -> dict[str, dict]:
    result = {}
    for block in data.decode().strip().split("\n\n"):
        sent_id = next((line.split(" = ", 1)[1] for line in block.splitlines() if line.startswith("# sent_id = ")), None)
        text = next((line.split(" = ", 1)[1] for line in block.splitlines() if line.startswith("# text = ")), None)
        if not sent_id or text is None:
            continue
        tokens = {}
        for line in block.splitlines():
            if line.startswith("#"):
                continue
            columns = line.split("\t")
            if len(columns) == 10 and columns[0].isdigit():
                tokens[columns[0]] = columns
        result[sent_id] = {"text": text, "tokens": tokens}
    return result


def build() -> dict:
    parsed = {name: parse(download(source)) for name, source in SOURCES.items()}
    cases = []
    for source_name, sent_id, token_id, weight in SELECTIONS:
        source = SOURCES[source_name]
        sentence = parsed[source_name][sent_id]
        token = sentence["tokens"][token_id]
        cases.append({
            "caseID": f"{source_name}:{sent_id}:{token_id}",
            "sourceID": source_name,
            "sourceSentenceID": sent_id,
            "languageCode": source["language"],
            "text": sentence["text"],
            "tokenID": token_id,
            "surface": token[1],
            "goldLemma": token[2],
            "goldUPOS": token[3],
            "goldXPOS": token[4],
            "goldFeatures": token[5],
            "occurrenceWeight": weight,
        })
    return {"schemaVersion": 1, "release": "UD 2.18", "sources": SOURCES, "cases": cases}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", required=True, type=Path)
    args = parser.parse_args()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(build(), indent=2, sort_keys=True, ensure_ascii=False) + "\n")


if __name__ == "__main__":
    main()
