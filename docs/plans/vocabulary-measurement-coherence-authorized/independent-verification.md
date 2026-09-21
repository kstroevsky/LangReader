# Independent forward verification — authorized lineage

## Disposition

**PASS.** A fresh Level-3 verifier found no blocking issue and made no repository edits.

## Verified hashes

- Locked base: `868106f57e1fa78a0b0f03c3e4e0dd29d6161500ef6b8ed8d13bc05bcc6a1671`.
- Original review: `f5299abc0c32aa5fb1af34068aaad74e069d08bb274c455f737e06de2379bc5c`.
- New authorization: `762b97c9fff039b46f13d235a9e69b0eec1f37e7dcf29c7e7b1d9bf9a46f53f1`.
- Prior failed candidate: `1283794cae1af72d36249ad999fd52fd20f81e07f3b2df2145d31e3033de8ec3`.
- Consolidated delta: `77de2b1afe7c1c4c33ebe7387ca7473101347e417e560527935e06cbd42b786d`.
- Authorization delta: `52e0bd344f9ebbc66881f232f106f8879b42f2d3703595706d1aacd1815ae9eb`.
- Base ledger: `d11ff5931fed900d437b65f34e8f578747e95c86e2ce0373c10d04b60e06dbb1`.
- Target ledger: `90851e78d7f588310c45ed1fd3d9b0c9d9cebe8ac0b74c90e0bdf93e4655f6c1`.
- Candidate: `b218edcb4deff49af2e899553e196d562aa2de0e1a004e49b81bee134ba67512`.

## Reconstruction

The verifier reproduced the lineage byte-for-byte:

```text
base
 + original-delta.patch
 = attempt-1 candidate ba734ee8…

 + bounded-repairs.patch
 = prior terminally failed candidate 1283794c…

 + authorized-amendments.patch
 = authorized candidate b218edcb…
```

`authorized-amendments.patch` is exactly the live unified diff between the retained failed candidate and the new authorized candidate.

## Mechanical evidence

- Fresh `plan_guard.py verify`: **PASS**.
- Errors: 0; warnings: 0.
- Verification report SHA-256: `4d940031e5c76d3b1b232b4adbda3adbf7b8601185f3ca69f1fcdfc176c4f97d`.
- Changed sections: 10; added sections: 4; removed sections: 0.
- Ledger counts: 42 active, 12 deferred, 0 superseded.
- The prior and authorized target ledgers have identical 54-ID sets. Only `EVID-002`, `VALID-001`, `CAL-001`, and `STUDY-002` differ, exactly matching the authorization scope.
- Base-to-target added/changed IDs equal the consolidated delta's requirement-ID union.

## Terminal-finding resolution

### FINAL-001

**Resolved.** The candidate preserves the hash-locked `adjustedProbability`/`baseItemProbability` latent-knowledge mathematics while applying `AUTH-001` to remove the shared reliability cap from the observation model. Evidence-specific `ρ` values are used directly; tail contradictions update only `εknowledge`; runtime reconstruction and the offline fitter share one Core observation-model contract. No further mathematical policy was introduced.

### FINAL-002

**Resolved.** The candidate retains stratified audits, inclusion probabilities, participant/document clustering, holdouts, delayed retesting, and design-appropriate weighting. It deliberately leaves the estimator and interval construction unchosen and requires them to be frozen by a separately approved SAP before confirmatory collection and before outcome inspection. No unauthorized statistical method was selected.

## Preservation, interfaces, and negative controls

The verifier confirmed that all other exact contracts and negative controls survive, including evidence coefficients, thresholds, Beta/clamp behavior, difficulty formulas, sample counts, POS gates, migration behavior, warm-prior rules, privacy exclusions, release/performance gates, disabled modeling dimensions, and final verification commands. The candidate is standalone-coherent and its cross-interface chains are implementable.

## Non-blocking provenance note

`base.snapshot.json` records the sibling locked-base path. The sibling and authorized-directory base files are byte-identical and share SHA-256 `868106f5…6a1671`; regenerating a snapshot against the copied path would change only the snapshot's embedded path field.
