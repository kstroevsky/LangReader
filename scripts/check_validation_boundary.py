#!/usr/bin/env python3
"""Enforce the one-way production/validation SwiftPM boundary."""

from __future__ import annotations

import argparse
import json
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PRODUCTION_TARGETS = {"LeafReaderCore", "LeafReaderApp"}
VALIDATION_TARGET = "LeafReaderValidation"
FINAL_VALIDATION_TYPES = {
    "ConsentedValidationStudyDataset",
    "ConsentedValidationStudyPackageV2",
    "VocabularyDiagnosticBankConfiguration",
    "VocabularyDiagnosticBankKind",
    "VocabularyDiagnosticBankResult",
    "VocabularyDiagnosticCoverageMassCount",
    "VocabularyDiagnosticFixedBank",
    "VocabularyDiagnosticFixedBankItem",
    "VocabularyDiagnosticFixedBankResult",
    "VocabularyDiagnosticThetaPositionCount",
}
FINAL_CORE_FORBIDDEN_MEMBERS = {
    "diagnosticNaturalStopReason": re.compile(r"^\s*package\s+var\s+diagnosticNaturalStopReason\b", re.MULTILINE),
    "diagnosticKnownProbability(for:)": re.compile(r"^\s*package\s+func\s+diagnosticKnownProbability\s*\(", re.MULTILINE),
    "result(selectionOverride:)": re.compile(r"^\s*package\s+func\s+result\s*\(\s*selectionOverride\s*:", re.MULTILINE),
}
CONTINUATION_DECLARATION_RE = re.compile(
    r"^\s*(?P<access>public|package|internal|private|fileprivate)?\s*"
    r"(?P<mutation>mutating\s+)?func\s+nextQuestionForDiagnosticContinuation\s*\(",
    re.MULTILINE,
)
IMPORT_RE = re.compile(r"^\s*(?:@\w+\s+)*import\s+([A-Za-z_][A-Za-z_0-9]*)\b", re.MULTILINE)
DECLARATION_RE = re.compile(
    r"^\s*(?:(?:public|package|internal|private|fileprivate)\s+)?"
    r"(?:struct|enum|class|protocol|typealias)\s+([A-Za-z_][A-Za-z_0-9]*)\b",
    re.MULTILINE,
)


def dependency_names(target: dict) -> set[str]:
    names = set()
    for dependency in target.get("dependencies", []):
        for kind in ("byName", "target"):
            if kind in dependency:
                names.add(dependency[kind][0])
    return names


def graph_errors(package: dict) -> list[str]:
    errors = []
    targets = {target["name"]: target for target in package.get("targets", [])}
    required = PRODUCTION_TARGETS | {VALIDATION_TARGET}
    for name in sorted(required - targets.keys()):
        errors.append(f"missing target: {name}")
    if errors:
        return errors

    dependencies = {name: dependency_names(target) for name, target in targets.items()}
    if dependencies[VALIDATION_TARGET] != {"LeafReaderCore"}:
        errors.append("LeafReaderValidation must depend only on LeafReaderCore")
    for name in PRODUCTION_TARGETS:
        if VALIDATION_TARGET in dependencies[name]:
            errors.append(f"{name} depends on LeafReaderValidation")

    app_products = [product for product in package.get("products", []) if product.get("name") == "LeafReaderApp"]
    if len(app_products) != 1:
        errors.append("expected exactly one shipping LeafReaderApp product")
        return errors
    frontier = list(app_products[0].get("targets", []))
    visited = set()
    while frontier:
        name = frontier.pop()
        if name in visited:
            continue
        visited.add(name)
        frontier.extend(dependencies.get(name, set()) & targets.keys())
    if VALIDATION_TARGET in visited:
        errors.append("shipping LeafReaderApp product reaches LeafReaderValidation")
    for name in visited:
        if targets[name].get("type") == "test":
            errors.append(f"shipping product reaches test target: {name}")
    return errors


def import_errors(sources: dict[str, str]) -> list[str]:
    errors = []
    forbidden = {
        "LeafReaderCore": {"LeafReaderValidation", "LeafReaderApp"},
        "LeafReaderApp": {"LeafReaderValidation"},
        "LeafReaderValidation": {"LeafReaderApp"},
    }
    for target, source in sources.items():
        for imported in IMPORT_RE.findall(source):
            if imported in forbidden.get(target, set()):
                errors.append(f"{target} imports {imported}")
    return errors


def declaration_errors(sources: dict[str, str]) -> list[str]:
    errors = []
    for target in PRODUCTION_TARGETS:
        for name in DECLARATION_RE.findall(sources.get(target, "")):
            if name in FINAL_VALIDATION_TYPES:
                errors.append(f"{target} still declares validation-only {name}")
    return errors


def core_member_errors(sources: dict[str, str]) -> list[str]:
    core = sources.get("LeafReaderCore", "")
    errors = [
        f"LeafReaderCore still declares experimental {name}"
        for name, pattern in FINAL_CORE_FORBIDDEN_MEMBERS.items()
        if pattern.search(core)
    ]
    continuations = list(CONTINUATION_DECLARATION_RE.finditer(core))
    if len(continuations) != 1 or continuations[0].group("access") != "package" \
            or continuations[0].group("mutation") is None:
        errors.append("LeafReaderCore must declare exactly one package mutating continuation seam")
    return errors


def sources_by_target() -> dict[str, str]:
    result = {}
    for name in (*sorted(PRODUCTION_TARGETS), VALIDATION_TARGET):
        source_root = ROOT / "Sources" / name
        result[name] = "\n".join(path.read_text(encoding="utf-8") for path in sorted(source_root.rglob("*.swift")))
    return result


def self_test() -> None:
    package = {
        "products": [{"name": "LeafReaderApp", "targets": ["LeafReaderApp"]}],
        "targets": [
            {"name": "LeafReaderCore", "type": "regular", "dependencies": []},
            {"name": "LeafReaderValidation", "type": "regular", "dependencies": [{"byName": ["LeafReaderCore", None]}]},
            {"name": "LeafReaderApp", "type": "executable", "dependencies": [{"byName": ["LeafReaderCore", None]}]},
            {"name": "LeafReaderAppTests", "type": "test", "dependencies": [{"byName": ["LeafReaderApp", None]}, {"byName": ["LeafReaderValidation", None]}]},
        ],
    }
    assert graph_errors(package) == [], "test-only Validation dependency should be allowed"
    for source, target in (
        ("LeafReaderCore", "LeafReaderValidation"),
        ("LeafReaderApp", "LeafReaderValidation"),
        ("LeafReaderValidation", "LeafReaderApp"),
    ):
        invalid = json.loads(json.dumps(package))
        next(item for item in invalid["targets"] if item["name"] == source)["dependencies"].append(
            {"byName": [target, None]}
        )
        assert graph_errors(invalid), f"{source} -> {target} was accepted"
    invalid_product = json.loads(json.dumps(package))
    invalid_product["products"][0]["targets"].append("LeafReaderValidation")
    assert graph_errors(invalid_product), "shipping Validation reachability was accepted"
    assert import_errors({"LeafReaderCore": "import LeafReaderValidation\n"})
    assert import_errors({"LeafReaderApp": "@testable import LeafReaderValidation\n"})
    assert import_errors({"LeafReaderValidation": "import LeafReaderApp\n"})
    assert import_errors({"LeafReaderCore": "// import LeafReaderValidation\n"}) == []
    assert declaration_errors({"LeafReaderCore": "package enum VocabularyDiagnosticBankKind {}\n"})
    assert declaration_errors({"LeafReaderCore": "// package enum VocabularyDiagnosticBankKind {}\n"}) == []
    valid_core = "package mutating func nextQuestionForDiagnosticContinuation() {}\n"
    assert core_member_errors({"LeafReaderCore": valid_core}) == []
    for invalid in (
        "package var diagnosticNaturalStopReason: Int { 0 }\n",
        "package func diagnosticKnownProbability(for key: String) -> Double { 0 }\n",
        "package func result(selectionOverride: Set<String> = []) {}\n",
        "private mutating func nextQuestionForDiagnosticContinuation() {}\n",
        "package mutating func nextQuestionForDiagnosticContinuation() {}\n" * 2,
    ):
        assert core_member_errors({"LeafReaderCore": valid_core + invalid}), f"accepted Core method fixture: {invalid}"
    assert core_member_errors({"LeafReaderCore": valid_core + "// package func diagnosticKnownProbability() {}\n"}) == []
    print("validation boundary negative fixtures passed")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--self-test", action="store_true")
    parser.add_argument("--final", action="store_true", help="reject validation-only declarations left in production")
    args = parser.parse_args()
    if args.self_test:
        self_test()
    try:
        package = json.loads(subprocess.check_output(["swift", "package", "dump-package"], cwd=ROOT, text=True))
    except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
        raise SystemExit(f"validation boundary infrastructure failure: {error}") from error
    errors = graph_errors(package)
    sources = sources_by_target()
    errors.extend(import_errors(sources))
    if args.final:
        errors.extend(declaration_errors(sources))
        errors.extend(core_member_errors(sources))
    if errors:
        raise SystemExit("validation boundary FAILED:\n  " + "\n  ".join(errors))
    print("validation boundary ok: production cannot depend on Validation")


if __name__ == "__main__":
    main()
