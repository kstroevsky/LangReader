# Warm question-path forensic checkpoint — 2026-09-13

## Outcome

The selected-case forensic slice is complete after one retained reporting failure
and one predeclared mechanical repair. It changes no production behavior and
does not estimate a population failure rate.

Attempt v1 ran from clean revision `11844eb`, matched all source paths, and was
retained as incomplete because it omitted unasked final inventory rows. Repair
v2 was frozen before implementation, ran from clean revision `fada508`, and
preserved every selected run, original path metric, and question trace while
adding only the missing final rows.

## Findings

All seven severe selected warm paths first diverged from their cold path at
ordinal 4, where the eligible warm assessment uses current-document tail
validation and the cold assessment uses ordinary initial calibration.

Across those seven warm-natural paths:

- total missed occurrence mass was 6,200;
- 5,518 (89%) belonged to asked, truly unknown items that received
  known-supporting evidence (`verifiedKnown` in these traces);
- 682 (11%) belonged to never-asked items.

Therefore the frozen “never-asked omissions dominate” hypothesis is not
supported in these cases. The primary shared mechanism is a path interaction:
warm validation changes subsequent question exposure, a fallible known response
lands on a high-occurrence unknown item, and the early/final deck logic omits
that item. The same mechanism appears across all four represented scenario
families, not only the explicit biased-self-verification scenario.

This does not establish that production users make such errors at the synthetic
rates, and it does not justify distrusting verified answers globally. It shows
why pooled averages and a two-answer compatibility likelihood fail to control
the selected severe tails.

## Evidence integrity

- 11/11 selected run IDs match the frozen selection rule.
- Schema-5 validator conserves assessable mass, missed mass, selected count,
  asked/evidence state, and question/final-item identity.
- V1/V2 parity passed for every original path field and question trace.
- Semantic report SHA-256:
  `44a583a775760030eb22fd89dc5e30ec4f4a969d2ed8a0a7cd181e818fc103c5`.
- [Incomplete v1 attempt](warm-question-path-forensic-attempt-v1.md)
- [Repair reservation](warm-question-path-forensic-repair-manifest-v2.json)
- [Repaired semantic report](warm-question-path-forensic-report-v2.json)
- [Forensic analysis](warm-question-path-forensic-analysis-v2.md)
- [Raw timings](warm-question-path-forensic-timing-v2.json)

## Next boundary

Do not tune the rejected likelihood threshold or bind development-confirmation.
A new mitigation experiment must be frozen before execution and must directly
address high-consequence erroneous known evidence—for example through a
predeclared consequence-aware confirmation or conservative deck rule—while
measuring added questions/cards and preserving honest known responses. The
selected 11 cases may inform mechanism design but cannot serve as the candidate's
acceptance set.
