#!/usr/bin/env python3
from __future__ import annotations

import argparse
import hashlib
import json
import math
import random
import unicodedata
from collections import defaultdict
from itertools import combinations
from pathlib import Path


CHECKPOINT_IDS = ("A", "B", "C")
BOOTSTRAP_METRICS = (
    "jointLemmaPartOfSpeechCorrectnessAllOccurrences",
    "resolvedOccurrenceCoverage",
    "jointLemmaPartOfSpeechAccuracyWhenResolved",
    "b3Precision",
    "b3Recall",
    "b3F1",
    "falseSplitPairRate",
    "falseMergePairRate",
)


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def ratio(numerator: int, denominator: int) -> float | None:
    return numerator / denominator if denominator else None


def ratio_zero(numerator: int, denominator: int) -> float:
    return numerator / denominator if denominator else 0.0


def wilson95(successes: int, total: int) -> dict | None:
    if total <= 0:
        return None
    z = 1.959963984540054
    p = successes / total
    denominator = 1 + z * z / total
    center = (p + z * z / (2 * total)) / denominator
    radius = z * math.sqrt(p * (1 - p) / total + z * z / (4 * total * total)) / denominator
    return {
        "lowerBound": max(0.0, center - radius),
        "upperBound": min(1.0, center + radius),
    }


def percentile(values: list[float], probability: float) -> float:
    if not values:
        raise ValueError("cannot compute percentile of an empty sample")
    ordered = sorted(values)
    if len(ordered) == 1:
        return ordered[0]
    position = probability * (len(ordered) - 1)
    lower = int(math.floor(position))
    upper = int(math.ceil(position))
    if lower == upper:
        return ordered[lower]
    weight = position - lower
    return ordered[lower] * (1 - weight) + ordered[upper] * weight


def canonical_lemma(value: str) -> str:
    return unicodedata.normalize("NFC", value.strip()).lower()


def escape_key_component(value: str) -> str:
    return value.replace("%", "%25").replace("|", "%7C")


def lexical_key(language: str, lemma: str, part_of_speech: str) -> str:
    return "|".join(
        escape_key_component(value)
        for value in (language.lower(), canonical_lemma(lemma), part_of_speech, "")
    )


def physical_occurrence_id(occurrence: dict) -> str:
    return (
        f"u{occurrence['sampledUnitIndex']}:"
        f"{occurrence['utf16Location']}:{occurrence['utf16Length']}"
    )


def prediction_for(rows: list[dict], expected_surface: str) -> dict:
    if rows and not any(row.get("surface") == expected_surface for row in rows):
        raise ValueError("checkpoint output surface does not match frozen gold occurrence range")
    keys = sorted(
        {
            row["finalLexicalKey"]
            for row in rows
            if isinstance(row.get("finalLexicalKey"), str) and row["finalLexicalKey"]
        }
    )
    states = sorted(
        {
            row["resolutionState"]
            for row in rows
            if isinstance(row.get("resolutionState"), str) and row["resolutionState"]
        }
    )
    routed = sorted(
        {
            row["routedLanguage"]
            for row in rows
            if isinstance(row.get("routedLanguage"), str) and row["routedLanguage"]
        }
    )
    detected = sorted(
        {
            row["detectedLanguage"]
            for row in rows
            if isinstance(row.get("detectedLanguage"), str) and row["detectedLanguage"]
        }
    )
    providers = sorted(
        {
            provider
            for row in rows
            for provider in row.get("providers", [])
            if isinstance(provider, str)
        }
    )
    return {
        "predictedLexicalKey": keys[0] if len(keys) == 1 else None,
        "distinctResolvedKeyCount": len(keys),
        "assignmentCount": len(rows),
        "resolutionState": states[0] if len(states) == 1 else None,
        "routedLanguage": routed[0] if len(routed) == 1 else None,
        "detectedLanguage": detected[0] if len(detected) == 1 else None,
        "providers": providers,
    }


def b3_metrics(resolved: list[dict], checkpoint: str) -> tuple[float, float, float] | None:
    if not resolved:
        return None
    predicted: dict[tuple[str, str], list[dict]] = defaultdict(list)
    gold: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in resolved:
        scope = row.get("_scope", row["documentID"])
        predicted[(scope, row["predictions"][checkpoint]["predictedLexicalKey"])].append(row)
        gold[(scope, row["goldLexicalKey"])].append(row)

    precision = 0.0
    recall = 0.0
    for row in resolved:
        scope = row.get("_scope", row["documentID"])
        predicted_cluster = predicted[(scope, row["predictions"][checkpoint]["predictedLexicalKey"])]
        gold_cluster = gold[(scope, row["goldLexicalKey"])]
        intersection = sum(
            candidate["goldLexicalKey"] == row["goldLexicalKey"]
            for candidate in predicted_cluster
        )
        precision += intersection / len(predicted_cluster)
        recall += intersection / len(gold_cluster)
    precision /= len(resolved)
    recall /= len(resolved)
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    return precision, recall, f1


def metrics(observations: list[dict], checkpoint: str) -> dict:
    total = len(observations)
    resolved = [
        row
        for row in observations
        if row["predictions"][checkpoint]["predictedLexicalKey"] is not None
    ]
    correct = [
        row
        for row in resolved
        if row["predictions"][checkpoint]["predictedLexicalKey"] == row["goldLexicalKey"]
    ]
    output_covered = [
        row for row in observations if row["predictions"][checkpoint]["assignmentCount"] > 0
    ]
    multi = [
        row
        for row in observations
        if row["predictions"][checkpoint]["distinctResolvedKeyCount"] > 1
    ]

    anchors: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in observations:
        scope = row.get("_scope", row["documentID"])
        anchors[(scope, row["goldAnchor"])].append(row)
    fully_resolved_anchor_count = sum(
        all(item["predictions"][checkpoint]["predictedLexicalKey"] is not None for item in rows)
        for rows in anchors.values()
    )
    predicted_splits = 0
    correct_predicted_splits = 0
    false_split_pairs = 0
    same_gold_pairs = 0
    false_merge_pairs = 0
    different_gold_pairs = 0
    for rows in anchors.values():
        anchor_resolved = [
            row
            for row in rows
            if row["predictions"][checkpoint]["predictedLexicalKey"] is not None
        ]
        predicted_keys = {
            row["predictions"][checkpoint]["predictedLexicalKey"] for row in anchor_resolved
        }
        gold_keys = {row["goldLexicalKey"] for row in rows}
        if len(predicted_keys) > 1:
            predicted_splits += 1
            if len(gold_keys) > 1:
                correct_predicted_splits += 1
        for lhs, rhs in combinations(anchor_resolved, 2):
            lhs_prediction = lhs["predictions"][checkpoint]["predictedLexicalKey"]
            rhs_prediction = rhs["predictions"][checkpoint]["predictedLexicalKey"]
            if lhs["goldLexicalKey"] == rhs["goldLexicalKey"]:
                same_gold_pairs += 1
                false_split_pairs += lhs_prediction != rhs_prediction
            else:
                different_gold_pairs += 1
                false_merge_pairs += lhs_prediction == rhs_prediction

    b3 = b3_metrics(resolved, checkpoint)
    split_precision = ratio(correct_predicted_splits, predicted_splits)
    ambiguous_occurrences = sum(
        row["predictions"][checkpoint]["resolutionState"] == "ambiguous"
        for row in observations
    )
    explicitly_unresolved_occurrences = sum(
        row["predictions"][checkpoint]["resolutionState"] == "unresolved"
        for row in observations
    )

    routed_available = [
        row
        for row in observations
        if row["predictions"][checkpoint]["routedLanguage"] is not None
    ]
    routed_correct = [
        row
        for row in routed_available
        if row["predictions"][checkpoint]["routedLanguage"] == row["language"]
    ]
    false_english = sum(
        row["language"] != "en"
        and (row["predictions"][checkpoint]["routedLanguage"] or "").split("-")[0] == "en"
        for row in observations
    )

    return {
        "occurrenceCount": total,
        "outputCoveredOccurrenceCount": len(output_covered),
        "outputOccurrenceCoverage": ratio_zero(len(output_covered), total),
        "resolvedOccurrenceCount": len(resolved),
        "resolvedOccurrenceCoverage": ratio_zero(len(resolved), total),
        "resolvedAnchorCount": fully_resolved_anchor_count,
        "goldAnchorCount": len(anchors),
        "resolvedAnchorCoverage": ratio_zero(fully_resolved_anchor_count, len(anchors)),
        "jointLemmaPartOfSpeechCorrectnessAllOccurrences": ratio_zero(len(correct), total),
        "jointLemmaPartOfSpeechAccuracyWhenResolved": ratio(len(correct), len(resolved)),
        "b3Precision": b3[0] if b3 else None,
        "b3Recall": b3[1] if b3 else None,
        "b3F1": b3[2] if b3 else None,
        "predictedSplitCount": predicted_splits,
        "correctPredictedSplitCount": correct_predicted_splits,
        "splitPrecision": split_precision,
        "splitPrecisionWilson95": wilson95(correct_predicted_splits, predicted_splits),
        "falseSplitPairRate": ratio(false_split_pairs, same_gold_pairs),
        "falseMergePairRate": ratio(false_merge_pairs, different_gold_pairs),
        "sameGoldPairCount": same_gold_pairs,
        "differentGoldPairCount": different_gold_pairs,
        "multipleResolvedAssignmentOccurrenceCount": len(multi),
        "missingCheckpointOutputOccurrenceCount": total - len(output_covered),
        "ambiguousOccurrenceRate": ratio_zero(ambiguous_occurrences, total),
        "explicitlyUnresolvedOccurrenceRate": ratio_zero(explicitly_unresolved_occurrences, total),
        "routedLanguageCoverage": ratio_zero(len(routed_available), total),
        "routedLanguageAccuracyWhenResolved": ratio(len(routed_correct), len(routed_available)),
        "falseEnglishFallbackCount": false_english,
    }


def grouped_metrics(
    observations: list[dict],
    checkpoint: str,
    dimension: str,
) -> list[dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in observations:
        if dimension == "document":
            value = row["documentID"]
        else:
            value = str(row[dimension])
        grouped[value].append(row)
    return [
        {"value": value, "metrics": metrics(rows, checkpoint)}
        for value, rows in sorted(grouped.items())
    ]


def macro_mean(groups: list[dict]) -> dict:
    fields = (
        "resolvedOccurrenceCoverage",
        "resolvedAnchorCoverage",
        "jointLemmaPartOfSpeechCorrectnessAllOccurrences",
        "jointLemmaPartOfSpeechAccuracyWhenResolved",
        "b3Precision",
        "b3Recall",
        "b3F1",
        "falseSplitPairRate",
        "falseMergePairRate",
    )
    result: dict[str, float | None] = {}
    for field in fields:
        values = [
            row["metrics"][field]
            for row in groups
            if row["metrics"].get(field) is not None
        ]
        result[field] = sum(values) / len(values) if values else None
    return result


def paired_bootstrap(
    observations: list[dict],
    checkpoint_from: str,
    checkpoint_to: str,
    replicates: int | None,
    confidence: float,
    seed: int,
) -> dict:
    point_from = metrics(observations, checkpoint_from)
    point_to = metrics(observations, checkpoint_to)
    result = {
        "from": checkpoint_from,
        "to": checkpoint_to,
        "pointDeltas": {
            field: (
                point_to[field] - point_from[field]
                if point_to.get(field) is not None and point_from.get(field) is not None
                else None
            )
            for field in BOOTSTRAP_METRICS
        },
    }
    if not replicates:
        result["bootstrap"] = {
            "status": "notRun",
            "reason": "bootstrap replicate count is not frozen",
        }
        return result

    by_family: dict[str, list[dict]] = defaultdict(list)
    for row in observations:
        by_family[row["workFamilyID"]].append(row)
    families = sorted(by_family)
    if not families:
        raise ValueError("no work-family clusters are available for bootstrap")
    rng = random.Random(seed)
    samples: dict[str, list[float]] = {field: [] for field in BOOTSTRAP_METRICS}
    for _ in range(replicates):
        selected = [families[rng.randrange(len(families))] for _ in families]
        resampled: list[dict] = []
        for draw_index, family in enumerate(selected):
            for row in by_family[family]:
                clone = dict(row)
                clone["_scope"] = f"{draw_index}|{row['documentID']}"
                resampled.append(clone)
        before = metrics(resampled, checkpoint_from)
        after = metrics(resampled, checkpoint_to)
        for field in BOOTSTRAP_METRICS:
            lhs = before.get(field)
            rhs = after.get(field)
            if lhs is not None and rhs is not None:
                samples[field].append(rhs - lhs)

    alpha = (1 - confidence) / 2
    intervals: dict[str, dict | None] = {}
    for field, values in samples.items():
        intervals[field] = (
            {
                "lowerBound": percentile(values, alpha),
                "upperBound": percentile(values, 1 - alpha),
                "replicateCount": len(values),
            }
            if values
            else None
        )
    result["bootstrap"] = {
        "status": "complete",
        "cluster": "workFamilyID",
        "confidence": confidence,
        "replicates": replicates,
        "seed": seed,
        "intervals": intervals,
    }
    return result


def annotation_map(gold: dict, directories: list[Path]) -> dict[str, dict]:
    expected = {row["annotationSHA256"]: row for row in gold["documents"]}
    found: dict[str, dict] = {}
    for directory in directories:
        for path in sorted(directory.expanduser().resolve().rglob("*.json")):
            try:
                raw = path.read_bytes()
                digest = hashlib.sha256(raw).hexdigest()
                if digest not in expected:
                    continue
                value = json.loads(raw)
            except (OSError, json.JSONDecodeError):
                continue
            if digest in found:
                raise ValueError(f"duplicate copies of frozen annotation {digest}")
            found[digest] = value
    missing = sorted(set(expected) - set(found))
    if missing:
        raise ValueError(f"could not locate {len(missing)} frozen annotation files")
    return found


def export_path(root: Path, document_id: str, alias: str, checkpoint: str, single: bool) -> Path:
    name = f"checkpoint-{checkpoint.lower()}.json"
    candidates = [
        root / document_id / name,
        root / alias / name,
    ]
    if single:
        candidates.append(root / name)
    existing = [path for path in candidates if path.exists()]
    if len(existing) != 1:
        raise ValueError(
            f"expected exactly one {checkpoint} export for {document_id}; found {len(existing)}"
        )
    return existing[0]


def validate_confirmatory_freeze(
    freeze_path: Path,
    corpus_path: Path,
    gold_path: Path,
    rules_path: Path,
    checkpoints: dict,
) -> None:
    freeze = json.loads(freeze_path.read_text(encoding="utf-8"))
    corpus = json.loads(corpus_path.read_text(encoding="utf-8"))
    gold = json.loads(gold_path.read_text(encoding="utf-8"))
    if freeze.get("status") != "frozen":
        raise ValueError("confirmatory freeze record is not frozen")
    if freeze.get("checkpoints") != checkpoints:
        raise ValueError("confirmatory freeze checkpoint revisions differ from the corpus")
    if gold.get("panel") != "representative" or freeze.get("goldPanel") != "representative":
        raise ValueError("confirmatory freeze must bind representative-panel gold")
    expected = {
        "corpusManifestSHA256": sha256_file(corpus_path),
        "goldManifestSHA256": sha256_file(gold_path),
        "analysisRulesSHA256": sha256_file(rules_path),
        "analysisCodeSHA256": sha256_file(Path(__file__).resolve()),
    }
    for field, value in expected.items():
        if freeze.get(field) != value:
            raise ValueError(f"confirmatory freeze {field} does not match the current artifact")
    frozen_documents = {
        (
            row.get("documentID"),
            row.get("sourceSHA256"),
            row.get("annotationSHA256"),
            row.get("sampledTextSHA256"),
        )
        for row in freeze.get("documents", [])
    }
    gold_documents = {
        (
            row.get("documentID"),
            row.get("sourceSHA256"),
            row.get("annotationSHA256"),
            row.get("sampledTextSHA256"),
        )
        for row in gold.get("documents", [])
    }
    if frozen_documents != gold_documents:
        raise ValueError("confirmatory freeze document/sample population differs from frozen gold")
    policies = {
        row.get("candidateSelectionPolicyVersion") for row in gold.get("documents", [])
    }
    expected_policy = corpus.get("samplingPolicies", {}).get("representative")
    if policies != {expected_policy} or freeze.get("samplingPolicy") != expected_policy:
        raise ValueError("confirmatory freeze sampling policy differs from frozen gold/corpus")


def occurrence_count_band(count: int) -> str:
    if count <= 1:
        return "1"
    if count <= 3:
        return "2-3"
    if count <= 7:
        return "4-7"
    return "8+"


def add_gold_strata(observations: list[dict]) -> None:
    anchors: dict[tuple[str, str], list[dict]] = defaultdict(list)
    for row in observations:
        anchors[(row["documentID"], row["goldAnchor"])].append(row)
    for rows in anchors.values():
        gold_keys = {row["goldLexicalKey"] for row in rows}
        partition = "singlePOS" if len(gold_keys) == 1 else "multiplePOS"
        count_band = occurrence_count_band(len(rows))
        for row in rows:
            row["goldPartition"] = partition
            row["occurrenceCountBand"] = count_band


def build_observations(
    corpus: dict,
    gold: dict,
    annotations: dict[str, dict],
    exports_root: Path,
) -> tuple[list[dict], dict]:
    corpus_by_id = {row["documentID"]: row for row in corpus["documents"]}
    single = len(gold["documents"]) == 1
    observations: list[dict] = []
    common_environment: dict | None = None
    harness_by_checkpoint: dict[str, str] = {}
    nlp_runtime_by_checkpoint: dict[str, set[str]] = defaultdict(set)
    language_selection_by_checkpoint: dict[str, set[str]] = defaultdict(set)
    dictionary_attestation_by_checkpoint: dict[str, set[str]] = defaultdict(set)
    common_environment_fields = (
        "osVersion",
        "osBuildVersion",
        "machineArchitecture",
        "xcodeVersion",
        "swiftVersion",
    )
    for gold_document in gold["documents"]:
        document_id = gold_document["documentID"]
        document = corpus_by_id.get(document_id)
        if document is None:
            raise ValueError(f"gold document {document_id} is absent from corpus manifest")
        annotation = annotations[gold_document["annotationSHA256"]]
        source = annotation["source"]
        if annotation.get("panel") != gold.get("panel"):
            raise ValueError(f"{document_id}: annotation panel differs from gold manifest")
        if (
            annotation.get("candidateSelectionPolicyVersion")
            != gold_document["candidateSelectionPolicyVersion"]
        ):
            raise ValueError(
                f"{document_id}: annotation candidate-selection policy differs from gold manifest"
            )
        if source.get("sourceSHA256") != document["sourceSHA256"]:
            raise ValueError(f"{document_id}: annotation source hash differs from corpus")
        if annotation.get("sampledTextSHA256") != gold_document["sampledTextSHA256"]:
            raise ValueError(f"{document_id}: annotation sampled-text hash differs from frozen gold")
        if source.get("sampledUnitNumbers") != gold_document["sampledUnitNumbers"]:
            raise ValueError(f"{document_id}: annotation sampled units differ from frozen gold")

        export_records: dict[str, dict[str, list[dict]]] = {}
        for checkpoint in CHECKPOINT_IDS:
            path = export_path(
                exports_root,
                document_id,
                str(gold_document.get("annotationAlias") or document_id),
                checkpoint,
                single,
            )
            value = json.loads(path.read_text(encoding="utf-8"))
            if value.get("checkpoint") != {
                "id": checkpoint,
                "revision": corpus["checkpoints"][checkpoint],
            }:
                raise ValueError(f"{document_id}: checkpoint {checkpoint} provenance mismatch")
            for field, expected in (
                ("sourceSHA256", document["sourceSHA256"]),
                ("annotationSHA256", gold_document["annotationSHA256"]),
                (
                    "candidateSelectionPolicyVersion",
                    gold_document["candidateSelectionPolicyVersion"],
                ),
                ("sampledTextSHA256", annotation["sampledTextSHA256"]),
                ("sampledUnitNumbers", source["sampledUnitNumbers"]),
                ("dataRole", document["dataRole"]),
            ):
                if value.get(field) != expected:
                    raise ValueError(f"{document_id}: checkpoint {checkpoint} {field} mismatch")
            environment = value.get("environment")
            if not isinstance(environment, dict):
                raise ValueError(f"{document_id}: checkpoint {checkpoint} has no runtime environment")
            current_common = {
                field: environment.get(field) for field in common_environment_fields
            }
            if any(not isinstance(item, str) or not item for item in current_common.values()):
                raise ValueError(
                    f"{document_id}: checkpoint {checkpoint} runtime environment is incomplete"
                )
            if common_environment is None:
                common_environment = current_common
            elif common_environment != current_common:
                raise ValueError(
                    "A/B/C book exports do not share one OS/architecture/Xcode/Swift runtime"
                )
            harness_sha = environment.get("experimentHarnessSHA256")
            if not isinstance(harness_sha, str) or len(harness_sha) != 64:
                raise ValueError(f"{document_id}: checkpoint {checkpoint} has no harness SHA-256")
            previous_harness = harness_by_checkpoint.setdefault(checkpoint, harness_sha)
            if previous_harness != harness_sha:
                raise ValueError(
                    f"checkpoint {checkpoint} experiment harness changed between documents"
                )
            for field, destination in (
                ("naturalLanguageRuntime", nlp_runtime_by_checkpoint),
                ("languageSelectionMode", language_selection_by_checkpoint),
                ("dictionaryAttestationState", dictionary_attestation_by_checkpoint),
            ):
                value_for_field = environment.get(field)
                if not isinstance(value_for_field, str) or not value_for_field:
                    raise ValueError(
                        f"{document_id}: checkpoint {checkpoint} environment is missing {field}"
                    )
                destination[checkpoint].add(value_for_field)
            grouped: dict[str, list[dict]] = defaultdict(list)
            for record in value.get("records", []):
                grouped[record["physicalOccurrenceID"]].append(record)
            export_records[checkpoint] = grouped

        seen_occurrences: set[str] = set()
        for anchor in annotation["anchors"]:
            for occurrence in anchor.get("occurrences", []):
                if occurrence.get("reviewStatus") != "approved":
                    continue
                occurrence_id = occurrence["occurrenceID"]
                if occurrence_id in seen_occurrences:
                    raise ValueError(f"{document_id}: duplicate approved occurrence {occurrence_id}")
                seen_occurrences.add(occurrence_id)
                physical_id = physical_occurrence_id(occurrence)
                gold_lemma = canonical_lemma(occurrence["goldLemma"])
                gold_pos = occurrence["goldPartOfSpeech"]
                row = {
                    "documentID": document_id,
                    "workFamilyID": document["workFamilyID"],
                    "genre": document["genre"],
                    "language": document["language"],
                    "documentFormat": document["documentFormat"],
                    "occurrenceID": occurrence_id,
                    "physicalOccurrenceID": physical_id,
                    "goldAnchor": f"{document['language']}|{gold_lemma}",
                    "goldLexicalKey": lexical_key(document["language"], gold_lemma, gold_pos),
                    "predictions": {},
                }
                for checkpoint in CHECKPOINT_IDS:
                    row["predictions"][checkpoint] = prediction_for(
                        export_records[checkpoint].get(physical_id, []),
                        occurrence["surface"],
                    )
                observations.append(row)
    if not observations:
        raise ValueError("no approved gold occurrences were available for analysis")
    add_gold_strata(observations)
    return observations, {
        "commonRuntime": common_environment,
        "experimentHarnessSHA256ByCheckpoint": harness_by_checkpoint,
        "naturalLanguageRuntimeByCheckpoint": {
            checkpoint: sorted(values)
            for checkpoint, values in nlp_runtime_by_checkpoint.items()
        },
        "languageSelectionModesByCheckpoint": {
            checkpoint: sorted(values)
            for checkpoint, values in language_selection_by_checkpoint.items()
        },
        "dictionaryAttestationStatesByCheckpoint": {
            checkpoint: sorted(values)
            for checkpoint, values in dictionary_attestation_by_checkpoint.items()
        },
    }


def analyze(
    corpus: dict,
    gold: dict,
    observations: list[dict],
    rules: dict,
) -> dict:
    macro_dimensions = rules.get("reporting", {}).get(
        "macroGroupings",
        ["document", "workFamilyID", "genre", "language", "documentFormat"],
    )
    dimensions = list(
        dict.fromkeys([*macro_dimensions, *rules.get("plannedStratification", [])])
    )
    checkpoint_reports: dict[str, dict] = {}
    for checkpoint in CHECKPOINT_IDS:
        strata = {
            dimension: grouped_metrics(observations, checkpoint, dimension)
            for dimension in dimensions
        }
        checkpoint_reports[checkpoint] = {
            "micro": metrics(observations, checkpoint),
            "strata": strata,
            "macroMeans": {
                dimension: macro_mean(groups)
                for dimension, groups in strata.items()
            },
        }

    bootstrap = rules.get("bootstrap", {})
    replicates = bootstrap.get("replicates")
    confidence = float(bootstrap.get("confidenceInterval", 0.95))
    seed = int(bootstrap.get("seed", 20261002))
    paired = {}
    for index, (lhs, rhs) in enumerate((("A", "B"), ("B", "C"), ("A", "C"))):
        paired[f"{lhs}->{rhs}"] = paired_bootstrap(
            observations,
            lhs,
            rhs,
            replicates,
            confidence,
            seed + index,
        )

    gates = rules.get("hardGates", {})
    gate_reports = {}
    for checkpoint in CHECKPOINT_IDS:
        summary = checkpoint_reports[checkpoint]["micro"]
        interval = summary["splitPrecisionWilson95"]
        gate_reports[checkpoint] = {
            "splitPrecisionTarget": gates.get("splitPrecisionMinimum"),
            "splitPrecisionWilson95LowerTarget": gates.get(
                "splitPrecisionWilson95LowerMinimum"
            ),
            "splitPrecisionObserved": summary["splitPrecision"],
            "splitPrecisionWilson95": interval,
            "passedOnNaturalBookGoldAnchors": (
                summary["splitPrecision"] is not None
                and interval is not None
                and summary["splitPrecision"] >= gates.get("splitPrecisionMinimum", 1.0)
                and interval["lowerBound"]
                >= gates.get("splitPrecisionWilson95LowerMinimum", 1.0)
            ),
        }

    margins = rules.get("nonInferiorityMargins", {})
    false_merge_margin = margins.get("falseMergeRate")
    false_merge_interval = (
        paired["B->C"].get("bootstrap", {})
        .get("intervals", {})
        .get("falseMergePairRate")
        if paired["B->C"].get("bootstrap", {}).get("status") == "complete"
        else None
    )
    if isinstance(false_merge_margin, (int, float)):
        false_merge_noninferiority = {
            "status": "evaluated" if false_merge_interval is not None else "notEvaluable",
            "direction": "lower-is-better",
            "maximumAcceptableIncrease": false_merge_margin,
            "delta": paired["B->C"]["pointDeltas"]["falseMergePairRate"],
            "bootstrapInterval": false_merge_interval,
            "passed": (
                false_merge_interval is not None
                and false_merge_interval["upperBound"] <= false_merge_margin
            ),
        }
    else:
        false_merge_noninferiority = {
            "status": "marginNotFrozen",
            "direction": "lower-is-better",
            "maximumAcceptableIncrease": None,
        }

    decision_metrics = (
        ("jointLemmaPartOfSpeechCorrectnessAllOccurrences", None),
        ("resolvedOccurrenceCoverage", None),
        ("b3Precision", None),
        ("b3Recall", None),
        ("b3F1", None),
        ("splitPrecision", "splitPrecisionMinimum"),
        ("falseSplitPairRate", None),
        ("falseMergePairRate", "nonInferiority:falseMergeRate"),
        ("routedLanguageCoverage", None),
        ("routedLanguageAccuracyWhenResolved", None),
    )
    decision_table = []
    for field, gate in decision_metrics:
        values = {
            checkpoint: checkpoint_reports[checkpoint]["micro"].get(field)
            for checkpoint in CHECKPOINT_IDS
        }
        decision_table.append(
            {
                "metric": field,
                **values,
                "A->B": (
                    values["B"] - values["A"]
                    if values["A"] is not None and values["B"] is not None
                    else None
                ),
                "B->C": (
                    values["C"] - values["B"]
                    if values["B"] is not None and values["C"] is not None
                    else None
                ),
                "A->C": (
                    values["C"] - values["A"]
                    if values["A"] is not None and values["C"] is not None
                    else None
                ),
                "gate": gate,
            }
        )

    stopping_rule = rules.get("stoppingEnrollmentRule", {})
    split_target = (
        stopping_rule.get("automaticSplitAdequacyTarget")
        if isinstance(stopping_rule, dict)
        else None
    )
    b_language_groups = checkpoint_reports["B"]["strata"].get("language", [])
    split_adequacy = {
        "checkpoint": "B",
        "targetPredictedAutomaticSplits": split_target,
        "observedPredictedAutomaticSplits": checkpoint_reports["B"]["micro"][
            "predictedSplitCount"
        ],
        "observedPredictedAutomaticSplitsByLanguage": {
            row["value"]: row["metrics"]["predictedSplitCount"]
            for row in b_language_groups
        },
        "meetsAdequacyTarget": (
            checkpoint_reports["B"]["micro"]["predictedSplitCount"] >= split_target
            if isinstance(split_target, int) and split_target > 0
            else None
        ),
        "targetMeaning": (
            stopping_rule.get("automaticSplitAdequacyTargetMeaning")
            if isinstance(stopping_rule, dict)
            else None
        ),
    }

    return {
        "schemaVersion": 1,
        "protocolVersion": corpus.get("protocolVersion"),
        "dataRole": gold.get("dataRole"),
        "goldPanel": gold.get("panel"),
        "goldStatus": gold.get("status"),
        "approvedOccurrenceCount": len(observations),
        "checkpointReports": checkpoint_reports,
        "pairedDeltas": paired,
        "decisionTable": decision_table,
        "automaticSplitEvidenceAdequacy": split_adequacy,
        "naturalBookSplitGateDiagnostics": gate_reports,
        "nonInferiorityDiagnostics": {
            "falseMergeRateBToC": false_merge_noninferiority,
            "assessmentInstabilityBToC": {
                "status": "notMeasuredByThisAnalyzer",
                "frozenMargin": margins.get("assessmentInstability"),
            },
        },
        "routingDiagnostics": {
            checkpoint: {
                "falseEnglishFallbackCount": checkpoint_reports[checkpoint]["micro"][
                    "falseEnglishFallbackCount"
                ],
                "routedLanguageCoverage": checkpoint_reports[checkpoint]["micro"][
                    "routedLanguageCoverage"
                ],
                "routedLanguageAccuracyWhenResolved": checkpoint_reports[checkpoint][
                    "micro"
                ]["routedLanguageAccuracyWhenResolved"],
            }
            for checkpoint in CHECKPOINT_IDS
        },
        "notMeasuredByThisAnalyzer": [
            "automatic splits with NLP deliberately unavailable",
            "definition-provider routing",
            "difficulty-provider routing",
            "cross-language persistence/cache isolation",
            "assessment question-path and deck consequences",
            "controlled PDF/EPUB/DOCX semantic parity",
        ],
    }


def self_test() -> None:
    def prediction(key: str | None) -> dict:
        return {
            "predictedLexicalKey": key,
            "distinctResolvedKeyCount": 1 if key else 0,
            "assignmentCount": 1,
            "resolutionState": "resolvedSingle" if key else "unresolved",
            "routedLanguage": "en",
            "detectedLanguage": None,
            "providers": [],
        }

    noun = lexical_key("en", "record", "noun")
    verb = lexical_key("en", "record", "verb")
    old = lexical_key("en", "record", "unknown")
    observations = []
    for index, gold_key in enumerate((noun, verb)):
        observations.append(
            {
                "documentID": "book-1",
                "workFamilyID": "work-1",
                "genre": "fiction",
                "language": "en",
                "documentFormat": "pdf",
                "occurrenceID": str(index),
                "goldAnchor": "en|record",
                "goldLexicalKey": gold_key,
                "predictions": {
                    "A": prediction(old),
                    "B": prediction(gold_key),
                    "C": prediction(gold_key),
                },
            }
        )
    add_gold_strata(observations)
    if {row["goldPartition"] for row in observations} != {"multiplePOS"}:
        raise AssertionError("self-test gold partition stratification changed")
    if {row["occurrenceCountBand"] for row in observations} != {"2-3"}:
        raise AssertionError("self-test occurrence-count stratification changed")
    before = metrics(observations, "A")
    after = metrics(observations, "B")
    if before["falseMergePairRate"] != 1.0:
        raise AssertionError("self-test baseline false merge was not detected")
    if after["jointLemmaPartOfSpeechAccuracyWhenResolved"] != 1.0:
        raise AssertionError("self-test correct split was not scored correctly")
    if after["predictedSplitCount"] != 1 or after["correctPredictedSplitCount"] != 1:
        raise AssertionError("self-test split accounting changed")
    boot = paired_bootstrap(observations, "A", "B", 50, 0.95, 7)
    if boot["bootstrap"]["status"] != "complete":
        raise AssertionError("self-test bootstrap did not run")
    print("representative-book checkpoint analyzer self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus-manifest", type=Path)
    parser.add_argument("--gold-manifest", type=Path)
    parser.add_argument("--analysis-rules", type=Path)
    parser.add_argument("--annotation-dir", type=Path, action="append", default=[])
    parser.add_argument("--exports-root", type=Path)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--confirmatory-freeze", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()

    if args.self_test:
        self_test()
        return 0
    required = (
        args.corpus_manifest,
        args.gold_manifest,
        args.analysis_rules,
        args.exports_root,
        args.output,
    )
    if any(value is None for value in required) or not args.annotation_dir:
        parser.error(
            "--corpus-manifest, --gold-manifest, --analysis-rules, --annotation-dir, "
            "--exports-root, and --output are required"
        )

    corpus = json.loads(args.corpus_manifest.read_text(encoding="utf-8"))
    gold = json.loads(args.gold_manifest.read_text(encoding="utf-8"))
    rules = json.loads(args.analysis_rules.read_text(encoding="utf-8"))
    if gold.get("checkpoints") != corpus.get("checkpoints"):
        raise ValueError("gold and corpus checkpoint provenance differ")
    if gold.get("dataRole") == "confirmatory":
        if gold.get("status") != "frozen":
            raise ValueError("confirmatory analysis requires frozen gold")
        if gold.get("panel") != "representative":
            raise ValueError("confirmatory analysis requires representative-panel gold")
        if rules.get("analysisStatus") != "frozen":
            raise ValueError("confirmatory analysis requires frozen analysis rules")
        if args.confirmatory_freeze is None:
            raise ValueError("confirmatory analysis requires --confirmatory-freeze")
        validate_confirmatory_freeze(
            args.confirmatory_freeze,
            args.corpus_manifest,
            args.gold_manifest,
            args.analysis_rules,
            corpus["checkpoints"],
        )

    annotations = annotation_map(gold, args.annotation_dir)
    observations, runtime_environment = build_observations(
        corpus,
        gold,
        annotations,
        args.exports_root.resolve(),
    )
    if gold.get("dataRole") == "confirmatory":
        freeze = json.loads(args.confirmatory_freeze.read_text(encoding="utf-8"))
        if (
            runtime_environment["experimentHarnessSHA256ByCheckpoint"]
            != freeze.get("checkpointExportHarnessSHA256")
        ):
            raise ValueError(
                "checkpoint exports were not produced by the harness frozen before confirmatory execution"
            )
    report = analyze(corpus, gold, observations, rules)
    report["runtimeEnvironment"] = runtime_environment
    report["provenance"] = {
        "corpusManifestSHA256": sha256_file(args.corpus_manifest),
        "goldManifestSHA256": sha256_file(args.gold_manifest),
        "analysisRulesSHA256": sha256_file(args.analysis_rules),
        "analysisCodeSHA256": sha256_file(Path(__file__).resolve()),
        "checkpoints": corpus["checkpoints"],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(
        json.dumps(report, indent=2, sort_keys=True) + "\n",
        encoding="utf-8",
    )
    print(f"wrote representative-book checkpoint analysis: {args.output}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
