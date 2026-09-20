# Vocabulary synthetic causal diagnostics — development checkpoint

Manifest schema: `1`; semantic schema: `1`; seed: `7`.
Source: `b2b99696feda177be0699d5277a2c13c7c7c9bd5`; dirty tree: `false` (status fingerprint `cbf29ce484222325`, source-content fingerprint `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`).

This is development-only synthetic evidence. It does not establish real-learner calibration, a release pass, or a unique causal explanation for a coverage miss.

- Runs retained in full: 1 (0 natural misses, 1 natural successes).
- Common-question/common-evidence replay directions retained: 2.
- Mean B1 − A lower-bound difference across retained natural-run replicas: -0.028512.
- Mean B2 − A lower-bound difference across retained natural-run replicas: -0.022504.
- Mean B2 − matched-B1 lower-bound difference across retained natural-run replicas: 0.006008.
- B1 repeats the exact 512 production theta positions with equal mass and independent latent draws. B2 uses independent within-stratum theta jitter and independent latent draws.
- The assessable denominator and missed mass use exact integers before conversion to coverage; excluded mass is reported separately.

Interpretation: systematic A/B discrepancies may be consistent with finite-bank selection optimism, while agreement with isolated truth misses is not proof of model misspecification. Null and adverse runs are retained.
