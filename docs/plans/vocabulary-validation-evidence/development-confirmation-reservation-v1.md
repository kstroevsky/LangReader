# Development confirmation reservation v1

This manifest seals the synthetic layer between reusable diagnostic development
and the frozen release holdout. It contains three independently derived seeds
and eight opaque document derivation identities per seed for the existing
64-reader, 400-lemma evaluator workload.

It has not been executed. No candidate or analysis freeze is attached, no
outcome artifact exists, no outcome was inspected, and release-holdout access
remains disallowed. Committing the seed root now prevents choosing a favorable
"fresh" confirmation set after later model development.

Before execution, a reviewer must bind the manifest to a clean candidate commit,
model/configuration/resource hashes, and a frozen analysis/decision-rule
checksum. The reservation is then consumed for that candidate-design cycle. If
its result motivates a design change, retain the result and reserve a new future
confirmation set; never relabel this one untouched.

Validate the seal without evaluating outcomes:

```sh
python3 scripts/validate_vocabulary_development_confirmation_reservation.py --self-test
python3 scripts/validate_vocabulary_development_confirmation_reservation.py \
  docs/plans/vocabulary-validation-evidence/development-confirmation-reservation-v1.json
```

The validator recomputes every run seed/document identity, verifies generator
and canonical-ledger hashes, proves non-overlap with known development and
release seeds, and rejects any premature candidate, outcome, consumption, or
release-access state. It never invokes the evaluator.
