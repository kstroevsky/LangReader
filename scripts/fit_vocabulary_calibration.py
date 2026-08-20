#!/usr/bin/env python3
"""Validate/merge disclosed LeafReader exports and fit an offline Rasch pack.

No network access is used. Packs are emitted with reviewed=false and therefore
cannot affect production until a human review changes that field deliberately.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import sys
from collections import defaultdict
from pathlib import Path

KNOWN = {"verifiedKnown": 1.0, "typedVerifiedKnown": 1.0, "legacyKnown": 1.0}
UNKNOWN = {
    "verifiedUnknownOrPartial": 0.0,
    "reportedUnknown": 0.0,
    "legacyUnknown": 0.0,
    "unsure": 0.25,
}
REQUIRED = {
    "languageCode", "lexicalItemID", "documentDomain", "difficultyMean",
    "difficultyStandardDeviation", "difficultySource", "difficultyVersion",
    "evidence", "protocolVersion", "sessionOrdinal",
}


def sigmoid(value: float) -> float:
    value = max(-30.0, min(30.0, value))
    return 1.0 / (1.0 + math.exp(-value))


def log_loss(y: float, p: float) -> float:
    p = max(1e-9, min(1 - 1e-9, p))
    return -(y * math.log(p) + (1 - y) * math.log(1 - p))


def load_exports(paths: list[Path]) -> list[dict]:
    rows: list[dict] = []
    seen: dict[tuple[str, str, int, str], tuple[str, float]] = {}
    for path in paths:
        payload = json.loads(path.read_text(encoding="utf-8"))
        if payload.get("schemaVersion") != 1:
            raise ValueError(f"{path}: unsupported schemaVersion")
        participant = payload.get("participant", {})
        pseudonym = participant.get("participantPseudonym", "").strip()
        if not pseudonym:
            raise ValueError(f"{path}: missing participant pseudonym")
        for record in payload.get("records", []):
            missing = REQUIRED - record.keys()
            if missing:
                raise ValueError(f"{path}: record missing {sorted(missing)}")
            evidence = record["evidence"]
            if evidence == "excluded":
                continue
            if evidence not in KNOWN and evidence not in UNKNOWN:
                raise ValueError(f"{path}: unknown evidence {evidence}")
            lexical = record["lexicalItemID"]
            for field in ("language", "lemma", "partOfSpeech"):
                if not lexical.get(field):
                    raise ValueError(f"{path}: lexicalItemID missing {field}")
            normalized = {
                **record,
                "participant": pseudonym,
                "l1": participant.get("firstLanguageCode"),
                "proficiency": participant.get("selfRatedProficiency"),
                "y": KNOWN.get(evidence, UNKNOWN.get(evidence)),
                "key": "|".join([
                    lexical["language"], lexical["lemma"], lexical["partOfSpeech"],
                    lexical.get("senseKey") or "",
                ]),
            }
            identity = (
                pseudonym,
                normalized["languageCode"],
                int(normalized["sessionOrdinal"]),
                normalized["key"],
            )
            signature = (normalized["evidence"], normalized["y"])
            if identity in seen:
                if seen[identity] != signature:
                    raise ValueError(f"{path}: conflicting duplicate evidence for {identity}")
                continue
            seen[identity] = signature
            rows.append(normalized)
    return rows


def fit_rasch(rows: list[dict], iterations: int = 35) -> tuple[dict, dict]:
    people = sorted({row["participant"] for row in rows})
    items = sorted({row["key"] for row in rows})
    theta = {person: 0.0 for person in people}
    prior = {}
    for item in items:
        item_rows = [row for row in rows if row["key"] == item]
        mean = sum(float(row["difficultyMean"]) for row in item_rows) / len(item_rows)
        sd = max(0.35, sum(float(row["difficultyStandardDeviation"]) for row in item_rows) / len(item_rows))
        prior[item] = (mean, sd)
    difficulty = {item: prior[item][0] for item in items}
    by_person = defaultdict(list)
    by_item = defaultdict(list)
    for row in rows:
        by_person[row["participant"]].append(row)
        by_item[row["key"]].append(row)
    for _ in range(iterations):
        for person, observations in by_person.items():
            gradient = -theta[person] / 6.25
            information = 1 / 6.25
            for row in observations:
                p = sigmoid(theta[person] - difficulty[row["key"]])
                gradient += row["y"] - p
                information += p * (1 - p)
            theta[person] = max(-6, min(6, theta[person] + gradient / max(information, 1e-6)))
        for item, observations in by_item.items():
            mean, sd = prior[item]
            precision = 1 / (sd * sd)
            gradient = -(difficulty[item] - mean) * precision
            information = precision
            for row in observations:
                p = sigmoid(theta[row["participant"]] - difficulty[item])
                gradient += p - row["y"]
                information += p * (1 - p)
            difficulty[item] = max(-6, min(6, difficulty[item] + gradient / max(information, 1e-6)))
    return theta, difficulty


def estimate_theta(
    observations: list[dict],
    difficulty: dict[str, float],
    slopes: dict[str, float] | None = None,
    iterations: int = 25,
) -> float:
    theta = 0.0
    slopes = slopes or {}
    for _ in range(iterations):
        gradient = -theta / 6.25
        information = 1 / 6.25
        for row in observations:
            item = row["key"]
            b = difficulty.get(item, float(row["difficultyMean"]))
            slope = slopes.get(item, 1.0)
            p = sigmoid(slope * (theta - b))
            gradient += slope * (row["y"] - p)
            information += slope * slope * p * (1 - p)
        theta = max(-6, min(6, theta + gradient / max(information, 1e-6)))
    return theta


def heldout_comparison(rows: list[dict], seed: int = 20260820) -> dict:
    participants = sorted({row["participant"] for row in rows})
    random.Random(seed).shuffle(participants)
    folds = {person: index % 5 for index, person in enumerate(participants)}
    rasch_losses, two_pl_losses = [], []
    stable_slopes: list[float] = []
    for fold in range(min(5, max(1, len(participants)))):
        train = [row for row in rows if folds[row["participant"]] != fold]
        test = [row for row in rows if folds[row["participant"]] == fold]
        if not train or not test:
            continue
        theta, difficulty = fit_rasch(train, 20)
        slopes = defaultdict(lambda: 1.0)
        # Conservative regularized discrimination estimates. Sparse/unstable
        # items remain at Rasch slope 1.
        by_item = defaultdict(list)
        for row in train:
            by_item[row["key"]].append(row)
        for item, observations in by_item.items():
            if len({row["participant"] for row in observations}) < 100:
                continue
            slope = 1.0
            for _ in range(12):
                gradient = -(slope - 1.0) / 0.25
                info = 1 / 0.25
                for row in observations:
                    person_theta = theta[row["participant"]]
                    delta = person_theta - difficulty[item]
                    p = sigmoid(slope * delta)
                    gradient += (row["y"] - p) * delta
                    info += p * (1 - p) * delta * delta
                slope = max(0.5, min(2.0, slope + gradient / max(info, 1e-6)))
            slopes[item] = slope
            stable_slopes.append(slope)
        by_test_person = defaultdict(list)
        for row in test:
            by_test_person[row["participant"]].append(row)
        for person, observations in by_test_person.items():
            ordered = sorted(
                observations,
                key=lambda row: hashlib.sha256(
                    f"{seed}:{fold}:{person}:{row['key']}:{row.get('sessionOrdinal', 0)}".encode()
                ).digest(),
            )
            split = max(1, len(ordered) // 2)
            calibration = ordered[:split]
            evaluation = ordered[split:]
            if not evaluation:
                continue
            rasch_theta = estimate_theta(calibration, difficulty)
            two_pl_theta = estimate_theta(calibration, difficulty, slopes)
            for row in evaluation:
                item = row["key"]
                b = difficulty.get(item, float(row["difficultyMean"]))
                rasch_losses.append(log_loss(row["y"], sigmoid(rasch_theta - b)))
                two_pl_losses.append(log_loss(row["y"], sigmoid(slopes[item] * (two_pl_theta - b))))
    rasch = sum(rasch_losses) / max(1, len(rasch_losses))
    two_pl = sum(two_pl_losses) / max(1, len(two_pl_losses))
    return {
        "participantHeldOutRaschLogLoss": rasch,
        "participantHeldOut2PLLogLoss": two_pl,
        "twoPLImprovement": rasch - two_pl,
        "twoPLEnabled": False,
        "requiredImprovement": 0.01,
        "stableDiscriminationItemCount": len(stable_slopes),
        "stableDiscriminationRange": [min(stable_slopes), max(stable_slopes)] if stable_slopes else None,
    }


def fit_pack(rows: list[dict], version: str) -> tuple[dict, dict]:
    theta, difficulty = fit_rasch(rows)
    by_item = defaultdict(list)
    for row in rows:
        by_item[row["key"]].append(row)
    items = []
    for key in sorted(by_item):
        observations = by_item[key]
        learners = len({row["participant"] for row in observations})
        info = sum(
            (lambda p: p * (1 - p))(sigmoid(theta[row["participant"]] - difficulty[key]))
            for row in observations
        )
        prior_sd = max(0.35, sum(float(row["difficultyStandardDeviation"]) for row in observations) / len(observations))
        standard_error = math.sqrt(1 / max(info + 1 / (prior_sd * prior_sd), 1e-9))
        residuals = defaultdict(list)
        standardized = []
        for row in observations:
            p = sigmoid(theta[row["participant"]] - difficulty[key])
            standardized.append((row["y"] - p) / math.sqrt(max(p * (1 - p), 1e-6)))
            group = f"{row.get('l1') or '-'}|{row.get('proficiency') or '-'}"
            residuals[group].append(row["y"] - p)
        eligible_groups = [values for values in residuals.values() if len(values) >= 30]
        dif = False
        if len(eligible_groups) >= 2:
            group_means = [sum(values) / len(values) for values in eligible_groups]
            dif = max(group_means) - min(group_means) >= 0.20
        lexical = observations[0]["lexicalItemID"]
        items.append({
            "lexicalItemID": lexical,
            "difficulty": difficulty[key],
            "standardError": standard_error,
            "independentLearnerCount": learners,
            "hasMaterialDIF": dif,
            "itemFitMeanSquare": sum(value * value for value in standardized) / len(standardized),
            "productionEligible": learners >= 100 and standard_error <= 0.35 and not dif,
        })
    comparison = heldout_comparison(rows)
    pack = {"version": version, "reviewed": False, "model": "rasch", "items": [
        {key: value for key, value in item.items() if key not in {"itemFitMeanSquare", "productionEligible"}}
        for item in items
    ]}
    report = {
        "participants": len({row["participant"] for row in rows}),
        "responses": len(rows),
        "items": len(items),
        "eligibleItems": sum(item["productionEligible"] for item in items),
        "itemsWithMaterialDIF": sum(item["hasMaterialDIF"] for item in items),
        **comparison,
    }
    return pack, report


def self_test() -> None:
    rows = []
    for person in range(120):
        theta = (person - 60) / 25
        for index, difficulty in enumerate((-1.0, 0.0, 1.0)):
            p = sigmoid(theta - difficulty)
            rows.append({
                "participant": f"p-{person}", "key": f"en|word{index}|noun|", "y": 1.0 if p >= 0.5 else 0.0,
                "difficultyMean": difficulty, "difficultyStandardDeviation": 0.5,
                "lexicalItemID": {"language": "en", "lemma": f"word{index}", "partOfSpeech": "noun"},
                "l1": "de" if person % 2 else "fr", "proficiency": "broad",
            })
    pack, report = fit_pack(rows, "self-test")
    assert len(pack["items"]) == 3
    assert report["participants"] == 120
    assert pack["reviewed"] is False
    print("vocabulary calibration self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("exports", nargs="*", type=Path)
    parser.add_argument("--output-pack", type=Path)
    parser.add_argument("--output-report", type=Path)
    parser.add_argument("--version", default="calibration-unreviewed-v1")
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if not args.exports:
        parser.error("provide at least one export")
    rows = load_exports(args.exports)
    if not rows:
        raise ValueError("no usable evidence records")
    pack, report = fit_pack(rows, args.version)
    report["inputSHA256"] = hashlib.sha256(
        b"".join(path.read_bytes() for path in sorted(args.exports))
    ).hexdigest()
    if args.output_pack:
        args.output_pack.write_text(json.dumps(pack, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    if args.output_report:
        args.output_report.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(report, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, json.JSONDecodeError) as error:
        print(f"error: {error}", file=sys.stderr)
        raise SystemExit(1)
