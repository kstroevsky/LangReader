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

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OBSERVATION_MANIFEST = ROOT / "scripts" / "fixtures" / "vocabulary-observation-model-v1.json"
REQUIRED = {
    "languageCode", "lexicalItemID", "documentDomain", "difficultyMean",
    "difficultyStandardDeviation", "difficultySource", "difficultyVersion",
    "evidence", "protocolVersion", "sessionOrdinal",
}


def sigmoid(value: float) -> float:
    value = max(-30.0, min(30.0, value))
    return 1.0 / (1.0 + math.exp(-value))


class ObservationModel:
    """Manifest-driven `P(E | K, rho)` shared with the Core runtime."""

    def __init__(self, path: Path):
        raw = path.read_bytes()
        payload = json.loads(raw)
        if payload.get("schemaVersion") != 1:
            raise ValueError(f"{path}: unsupported observation schemaVersion")
        for field in (
            "observationModelVersion", "knowledgeModelVersion", "reliabilitySourceVersion",
        ):
            if not isinstance(payload.get(field), str) or not payload[field]:
                raise ValueError(f"{path}: missing {field}")
        epsilon = payload.get("defaultEpsilonKnowledge")
        if not isinstance(epsilon, (int, float)) or not 0 <= epsilon <= 0.25:
            raise ValueError(f"{path}: invalid defaultEpsilonKnowledge")
        emissions = {}
        for entry in payload.get("evidence", []):
            evidence = entry.get("evidence")
            if not isinstance(evidence, str) or evidence == "excluded" or evidence in emissions:
                raise ValueError(f"{path}: invalid or duplicate observation evidence")
            try:
                values = tuple(float(entry[field]) for field in (
                    "reliability", "probabilityGivenKnown", "probabilityGivenUnknown",
                ))
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(f"{path}: malformed emission for {evidence}") from error
            if any(not 0 <= value <= 1 for value in values):
                raise ValueError(f"{path}: invalid emission probability for {evidence}")
            emissions[evidence] = {
                "reliability": values[0],
                "probabilityGivenKnown": values[1],
                "probabilityGivenUnknown": values[2],
            }
        if not emissions:
            raise ValueError(f"{path}: observation evidence is empty")
        self.path = path
        self.sha256 = hashlib.sha256(raw).hexdigest()
        self.observation_version = payload["observationModelVersion"]
        self.knowledge_version = payload["knowledgeModelVersion"]
        self.reliability_version = payload["reliabilitySourceVersion"]
        self.epsilon_knowledge = float(epsilon)
        self.emissions = emissions
        self.golden_fixtures = payload.get("goldenFixtures", [])
        self._validate_golden_fixtures(path)

    def latent_known_probability(
        self, theta: float, difficulty: float, epsilon_knowledge: float | None = None,
        slope: float = 1.0,
    ) -> float:
        epsilon = self.epsilon_knowledge if epsilon_knowledge is None else epsilon_knowledge
        base = sigmoid(slope * (theta - difficulty))
        return epsilon + (1 - 2 * epsilon) * base

    def likelihood(self, evidence: str, latent_known_probability: float) -> float:
        emission = self.emissions[evidence]
        return (
            latent_known_probability * emission["probabilityGivenKnown"]
            + (1 - latent_known_probability) * emission["probabilityGivenUnknown"]
        )

    def posterior_known_probability(self, evidence: str, prior: float) -> float:
        emission = self.emissions[evidence]
        known_joint = prior * emission["probabilityGivenKnown"]
        unknown_joint = (1 - prior) * emission["probabilityGivenUnknown"]
        total = known_joint + unknown_joint
        return known_joint / total if total > 0 else prior

    def terms(
        self, evidence: str, theta: float, difficulty: float, slope: float = 1.0,
    ) -> tuple[float, float]:
        """Returns likelihood and derivative with respect to `slope * (theta - b)`."""
        base = sigmoid(slope * (theta - difficulty))
        latent = self.epsilon_knowledge + (1 - 2 * self.epsilon_knowledge) * base
        emission = self.emissions[evidence]
        contrast = emission["probabilityGivenKnown"] - emission["probabilityGivenUnknown"]
        likelihood = self.likelihood(evidence, latent)
        derivative = contrast * (1 - 2 * self.epsilon_knowledge) * base * (1 - base)
        return max(likelihood, 1e-12), derivative

    def metadata(self) -> dict:
        return {
            "manifestSHA256": self.sha256,
            "observationModelVersion": self.observation_version,
            "knowledgeModelVersion": self.knowledge_version,
            "reliabilitySourceVersion": self.reliability_version,
            "epsilonKnowledge": self.epsilon_knowledge,
        }

    def _validate_golden_fixtures(self, path: Path) -> None:
        if not self.golden_fixtures:
            raise ValueError(f"{path}: observation golden fixtures are empty")
        for fixture in self.golden_fixtures:
            evidence = fixture.get("evidence")
            if evidence not in self.emissions:
                raise ValueError(f"{path}: golden fixture has unknown evidence {evidence}")
            try:
                latent = self.latent_known_probability(
                    float(fixture["theta"]),
                    float(fixture["difficulty"]),
                    float(fixture["epsilonKnowledge"]),
                )
            except (KeyError, TypeError, ValueError) as error:
                raise ValueError(f"{path}: malformed golden fixture for {evidence}") from error
            likelihood = self.likelihood(evidence, latent)
            posterior = self.posterior_known_probability(evidence, latent)
            expected = (
                ("latentKnownProbability", latent),
                ("evidenceLikelihood", likelihood),
                ("posteriorKnownProbability", posterior),
            )
            for field, actual in expected:
                try:
                    fixture_value = float(fixture[field])
                except (KeyError, TypeError, ValueError) as error:
                    raise ValueError(
                        f"{path}: malformed golden fixture for {evidence}.{field}"
                    ) from error
                if not math.isclose(actual, fixture_value, rel_tol=0, abs_tol=1e-12):
                    raise ValueError(f"{path}: golden fixture mismatch for {evidence}.{field}")


def fisher_information(likelihood: float, derivative: float) -> float:
    return derivative * derivative / max(likelihood * (1 - likelihood), 1e-9)


def load_exports(paths: list[Path], observation_model: ObservationModel) -> list[dict]:
    rows: list[dict] = []
    seen: dict[tuple[str, str, int, str], str] = {}
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
            if evidence not in observation_model.emissions:
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
            signature = normalized["evidence"]
            if identity in seen:
                if seen[identity] != signature:
                    raise ValueError(f"{path}: conflicting duplicate evidence for {identity}")
                continue
            seen[identity] = signature
            rows.append(normalized)
    return rows


def fit_rasch(
    rows: list[dict], observation_model: ObservationModel, iterations: int = 35,
) -> tuple[dict, dict]:
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
                likelihood, derivative = observation_model.terms(
                    row["evidence"], theta[person], difficulty[row["key"]]
                )
                gradient += derivative / likelihood
                information += fisher_information(likelihood, derivative)
            theta[person] = max(-6, min(6, theta[person] + gradient / max(information, 1e-6)))
        for item, observations in by_item.items():
            mean, sd = prior[item]
            precision = 1 / (sd * sd)
            gradient = -(difficulty[item] - mean) * precision
            information = precision
            for row in observations:
                likelihood, derivative = observation_model.terms(
                    row["evidence"], theta[row["participant"]], difficulty[item]
                )
                gradient -= derivative / likelihood
                information += fisher_information(likelihood, derivative)
            difficulty[item] = max(-6, min(6, difficulty[item] + gradient / max(information, 1e-6)))
    return theta, difficulty


def estimate_theta(
    observations: list[dict],
    difficulty: dict[str, float],
    observation_model: ObservationModel,
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
            likelihood, linear_derivative = observation_model.terms(
                row["evidence"], theta, b, slope
            )
            derivative = slope * linear_derivative
            gradient += derivative / likelihood
            information += fisher_information(likelihood, derivative)
        theta = max(-6, min(6, theta + gradient / max(information, 1e-6)))
    return theta


def heldout_comparison(
    rows: list[dict], observation_model: ObservationModel, seed: int = 20260820,
) -> dict:
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
        theta, difficulty = fit_rasch(train, observation_model, 20)
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
                    likelihood, linear_derivative = observation_model.terms(
                        row["evidence"], person_theta, difficulty[item], slope
                    )
                    derivative = linear_derivative * delta
                    gradient += derivative / likelihood
                    info += fisher_information(likelihood, derivative)
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
            rasch_theta = estimate_theta(calibration, difficulty, observation_model)
            two_pl_theta = estimate_theta(calibration, difficulty, observation_model, slopes)
            for row in evaluation:
                item = row["key"]
                b = difficulty.get(item, float(row["difficultyMean"]))
                rasch_likelihood, _ = observation_model.terms(
                    row["evidence"], rasch_theta, b
                )
                two_pl_likelihood, _ = observation_model.terms(
                    row["evidence"], two_pl_theta, b, slopes[item]
                )
                rasch_losses.append(-math.log(rasch_likelihood))
                two_pl_losses.append(-math.log(two_pl_likelihood))
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


def fit_pack(
    rows: list[dict], version: str, observation_model: ObservationModel,
) -> tuple[dict, dict]:
    theta, difficulty = fit_rasch(rows, observation_model)
    by_item = defaultdict(list)
    for row in rows:
        by_item[row["key"]].append(row)
    items = []
    for key in sorted(by_item):
        observations = by_item[key]
        learners = len({row["participant"] for row in observations})
        info = 0.0
        for row in observations:
            likelihood, linear_derivative = observation_model.terms(
                row["evidence"], theta[row["participant"]], difficulty[key]
            )
            info += fisher_information(likelihood, -linear_derivative)
        prior_sd = max(0.35, sum(float(row["difficultyStandardDeviation"]) for row in observations) / len(observations))
        standard_error = math.sqrt(1 / max(info + 1 / (prior_sd * prior_sd), 1e-9))
        residuals = defaultdict(list)
        standardized = []
        for row in observations:
            likelihood, linear_derivative = observation_model.terms(
                row["evidence"], theta[row["participant"]], difficulty[key]
            )
            derivative = -linear_derivative
            observation_information = fisher_information(likelihood, derivative)
            score = derivative / likelihood
            standardized.append(score / math.sqrt(max(observation_information, 1e-9)))
            group = f"{row.get('l1') or '-'}|{row.get('proficiency') or '-'}"
            residuals[group].append(score)
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
    comparison = heldout_comparison(rows, observation_model)
    pack = {
        "version": version,
        "reviewed": False,
        "model": "rasch",
        "observationModel": observation_model.metadata(),
        "items": [
            {
                key: value for key, value in item.items()
                if key not in {"itemFitMeanSquare", "productionEligible"}
            }
            for item in items
        ],
    }
    report = {
        "participants": len({row["participant"] for row in rows}),
        "responses": len(rows),
        "items": len(items),
        "eligibleItems": sum(item["productionEligible"] for item in items),
        "itemsWithMaterialDIF": sum(item["hasMaterialDIF"] for item in items),
        "observationModel": observation_model.metadata(),
        **comparison,
    }
    return pack, report


def self_test(observation_model: ObservationModel) -> None:
    for evidence in observation_model.emissions:
        likelihood, derivative = observation_model.terms(evidence, 0.4, -0.2)
        step = 1e-6
        upper = observation_model.likelihood(
            evidence,
            observation_model.latent_known_probability(0.4 + step, -0.2),
        )
        lower = observation_model.likelihood(
            evidence,
            observation_model.latent_known_probability(0.4 - step, -0.2),
        )
        assert likelihood > 0
        assert math.isclose(derivative, (upper - lower) / (2 * step), rel_tol=1e-7)

    rows = []
    for person in range(120):
        theta = (person - 60) / 25
        for index, difficulty in enumerate((-1.0, 0.0, 1.0)):
            latent_known = observation_model.latent_known_probability(theta, difficulty)
            rows.append({
                "participant": f"p-{person}", "key": f"en|word{index}|noun|",
                "evidence": "verifiedKnown" if latent_known >= 0.5 else "reportedUnknown",
                "difficultyMean": difficulty, "difficultyStandardDeviation": 0.5,
                "lexicalItemID": {"language": "en", "lemma": f"word{index}", "partOfSpeech": "noun"},
                "l1": "de" if person % 2 else "fr", "proficiency": "broad",
            })
    theta, difficulty = fit_rasch(rows, observation_model)
    assert min(theta.values()) < 0 < max(theta.values())
    assert difficulty["en|word0|noun|"] < difficulty["en|word1|noun|"]
    assert difficulty["en|word1|noun|"] < difficulty["en|word2|noun|"]
    pack, report = fit_pack(rows, "self-test", observation_model)
    assert len(pack["items"]) == 3
    assert report["participants"] == 120
    assert pack["reviewed"] is False
    assert pack["observationModel"] == observation_model.metadata()
    assert all("y" not in row for row in rows)
    print("vocabulary calibration self-test passed")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("exports", nargs="*", type=Path)
    parser.add_argument("--output-pack", type=Path)
    parser.add_argument("--output-report", type=Path)
    parser.add_argument("--version", default="calibration-unreviewed-v1")
    parser.add_argument("--observation-manifest", type=Path, default=DEFAULT_OBSERVATION_MANIFEST)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    observation_model = ObservationModel(args.observation_manifest)
    if args.self_test:
        self_test(observation_model)
        return 0
    if not args.exports:
        parser.error("provide at least one export")
    rows = load_exports(args.exports, observation_model)
    if not rows:
        raise ValueError("no usable evidence records")
    pack, report = fit_pack(rows, args.version, observation_model)
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
