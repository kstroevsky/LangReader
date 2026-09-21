# Warm question-path forensic result v2

This reporting-only repair preserves the same outcome-selected 11 cases and every v1 path/question trace. It changes no production configuration and makes no population claim.

Selected cases: 11 (7 severe, 4 deterministic controls).

Across the seven severe warm-natural paths, missed occurrence mass was 6200. Known-supporting evidence attached to truly unknown missed items accounted for 5518 (89.00%). Never-asked items accounted for 682 (11.00%).

| Run | Warm-cold coverage | First divergence | Warm missed mass | Asked verified-known miss | Unasked miss | Natural deck symmetric-difference mass |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| biased-self-verification:learner-3 | -7.559 pp | 4 | 980 | 915 | 65 | 3869 |
| biased-self-verification:learner-48 | -6.908 pp | 4 | 655 | 470 | 185 | 3943 |
| biased-self-verification:learner-57 | -6.853 pp | 4 | 856 | 709 | 147 | 3619 |
| changed-difficulty-distribution:learner-1 | -5.289 pp | 4 | 424 | 424 | 0 | 2446 |
| easy-history-hard-evaluation:learner-119 | -15.991 pp | 4 | 1155 | 1000 | 155 | 2883 |
| easy-history-hard-evaluation:learner-75 | -13.789 pp | 4 | 1130 | 1000 | 130 | 1688 |
| noisy-history:learner-111 | -13.845 pp | 4 | 1000 | 1000 | 0 | 4246 |

The frozen path-divergence and erroneous-known-evidence hypotheses are supported in these selected cases. The never-asked concentration hypothesis is not: most severe missed mass was asked and then received `verifiedKnown` evidence despite unknown synthetic truth. The same primary mechanism appears across biased-self-verification, noisy-history, difficulty-shift, and changed-distribution cases, so scenario-specificity is not the leading explanation here.

This does not mean the product should distrust verified user confirmations globally. It shows that rare false known-supporting evidence on a high-occurrence word can dominate coverage, and that an early warm path can expose a different such word before stopping. A mitigation requires a fresh design that addresses high-consequence evidence without tuning on these 11 cases.

Selected-case mechanism evidence only. The common mechanism is interaction between early warm path divergence, fallible verifiedKnown evidence on truly unknown high-occurrence items, and stopping/deck selection; case counts do not estimate prevalence or authorize mitigation.
