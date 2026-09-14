# Vocabulary longitudinal warm-start diagnostics — development checkpoint

Source `7fbc12a22fd0e9096ecd3221b9c82d4f7a5dbb3b`; dirty tree `false`; source fingerprint `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

This is development-only synthetic evidence through the real isolated SQLite prior store. It is not the historical oracle-informed reference, real-learner calibration, or release acceptance.

- Runs retained: 512; eligible warm runs: 319; ineligible warm runs: 193.
- Eligible-run mean natural question reduction: 72.358%.
- Eligible-run mean warm-minus-cold realized projected coverage: -0.2703 percentage points.
- Runs with adverse natural warm-minus-cold realized coverage: 150.
- Every evaluation preserves paired hidden truth and potential-response fingerprints across cold, warm, fixed-budget, and replay paths.
- Failed writes, duplicate contributions, abandoned work, reset, insufficient/low-verified/stale/future/incompatible histories remain explicit rather than being promoted to eligible history.

Interpretation remains scenario- and support-limited. Natural path differences mix prior, stopping, and selection effects; fixed-budget and bidirectional common-evidence replays provide conditional controls rather than unique causal proof.
