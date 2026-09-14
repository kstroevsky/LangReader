# Vocabulary synthetic causal diagnostics — development checkpoint

Manifest schema: `1`; semantic schema: `1`; seed: `20260908`.
Source: `e8ea803c2a9eb557677a520f4c97aacf729e7c52`; dirty tree: `true` (status fingerprint `f27ea91967e9655d`, source-content fingerprint `a13b6c3453858a3a92b8b73f46c69d4f8afb4a6e3c58a29958b8201eab659f29`).

This is development-only synthetic evidence. It does not establish real-learner calibration, a release pass, or a unique causal explanation for a coverage miss.

- Runs retained in full: 8 (1 natural misses, 7 natural successes).
- Common-question/common-evidence replay directions retained: 4.
- Mean B1 − A lower-bound difference across retained natural-run replicas: -0.001030.
- Mean B2 − A lower-bound difference across retained natural-run replicas: -0.001399.
- Mean B2 − matched-B1 lower-bound difference across retained natural-run replicas: -0.000369.
- B1 repeats the exact 512 production theta positions with equal mass and independent latent draws. B2 uses independent within-stratum theta jitter and independent latent draws.
- The assessable denominator and missed mass use exact integers before conversion to coverage; excluded mass is reported separately.

Interpretation: systematic A/B discrepancies may be consistent with finite-bank selection optimism, while agreement with isolated truth misses is not proof of model misspecification. Null and adverse runs are retained.
