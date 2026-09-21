# Final independent verification

Disposition: **FAIL — terminal bounded-repair stop**

## Recurring findings

### FINAL-001 — EVID-002 / VALID-001 / CAL-001

This recurs from `IF-005`.

The candidate requires the observation likelihood to be extracted without mathematical change from the hash-locked current Core source. That source caps evidence reliability with `min(reliability, 1 - errorFloor)`. The candidate also prohibits the shared cap and assigns tail-validation mismatch only to `εknowledge`. Both contracts cannot be implemented simultaneously.

The source path/hash provenance passes, but the requested separation requires an authorized mathematical change or a staged compatibility rule that the supplied review does not define exactly.

### FINAL-002 — STUDY-002

This recurs from `IF-003`.

The candidate still mandates weighted estimates with uncertainty intervals for stratified large-document audits. The review authorizes stratified audits, stored inclusion probabilities, and delayed retesting, but does not specify the estimator or interval policy. Selecting one would be new statistical policy.

## Additional provenance finding

The second failed candidate (`eca0f48d…f22a`) was recorded by hash and repair delta but was not preserved byte-for-byte in the durable plan directory. Attempt-1 artifacts and the final rebuilt candidate are retained.

## Passing evidence

- Base SHA-256: `868106f57e1fa78a0b0f03c3e4e0dd29d6161500ef6b8ed8d13bc05bcc6a1671`
- Review SHA-256: `f5299abc0c32aa5fb1af34068aaad74e069d08bb274c455f737e06de2379bc5c`
- Candidate SHA-256: `1283794cae1af72d36249ad999fd52fd20f81e07f3b2df2145d31e3033de8ec3`
- Fresh mechanical verification: PASS
- Ledger counts: 42 active, 12 deferred, 0 superseded
- Base → original delta → bounded repairs reproduces the current candidate byte-for-byte
- All unchanged base contracts and negative controls otherwise pass

## Stop condition

The same semantic failures recurred after two bounded repair cycles. Under the preservation protocol, no third repair is permitted without new source evidence or explicit user authorization. The candidate remains unaccepted and incomplete.
