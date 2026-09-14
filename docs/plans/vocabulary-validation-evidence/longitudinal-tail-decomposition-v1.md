# Vocabulary longitudinal warm-tail decomposition

This development-only analysis uses the existing two-percentage-point warm degradation boundary. It changes no production configuration and does not access development-confirmation or release-holdout data.

Material tails: 13; stopping implicated: 11; persistent at the common 60-question budget: 2.

| Run | Natural warm-cold | Fixed-budget warm-cold | Cold/warm questions | Classification |
| --- | ---: | ---: | ---: | --- |
| biased-self-verification:learner-22 | -13.762 pp | -14.468 pp | 60/13 | persists-at-fixed-budget |
| noisy-history:learner-13 | -13.125 pp | 0.000 pp | 60/11 | stopping-implicated |
| biased-self-verification:learner-23 | -8.487 pp | -13.845 pp | 60/16 | persists-at-fixed-budget |
| ability-drift:learner-0 | -2.700 pp | 0.000 pp | 60/12 | stopping-implicated |
| failed-write-retry:learner-31 | -2.617 pp | 0.000 pp | 55/15 | stopping-implicated |
| changed-difficulty-distribution:learner-5 | -2.575 pp | 0.000 pp | 59/16 | stopping-implicated |
| abandoned-session:learner-17 | -2.547 pp | -0.568 pp | 60/14 | stopping-implicated |
| abandoned-session:learner-6 | -2.451 pp | 0.000 pp | 60/11 | stopping-implicated |
| changed-difficulty-distribution:learner-24 | -2.409 pp | 0.000 pp | 50/11 | stopping-implicated |
| changed-difficulty-distribution:learner-17 | -2.257 pp | 0.706 pp | 60/11 | stopping-implicated |
| hard-history-easy-evaluation:learner-5 | -2.118 pp | 0.000 pp | 60/11 | stopping-implicated |
| easy-history-hard-evaluation:learner-7 | -2.049 pp | 0.000 pp | 60/23 | stopping-implicated |
| changed-difficulty-distribution:learner-15 | -2.035 pp | 0.000 pp | 49/11 | stopping-implicated |

Eleven of thirteen material natural failures cease to be material at the common budget, which implicates stopping under the tested paths. Two biased-self-verification failures persist and remain unattributed between changed question paths and transferred-prior/posterior effects.

Common-evidence replay does not currently report realized truth coverage, so fixed-budget-persistent failures cannot yet distinguish question selection from transferred-prior/posterior effects.

Next: extend development-only replay diagnostics with realized truth coverage before choosing a mitigation. Do not disable warm personalization, change the 0.90 weight, bind confirmation, or access the release holdout from this result.
