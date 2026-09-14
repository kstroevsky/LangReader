# Vocabulary longitudinal warm-tail decomposition

This development-only analysis uses the existing two-percentage-point warm degradation boundary. It changes no production configuration and does not access development-confirmation or release-holdout data.

Material tails: 13; stopping implicated: 11; persistent at the common 60-question budget: 2.

| Run | Natural warm-cold | Fixed-budget warm-cold | Path effect under cold/warm prior | Prior effect on cold/warm path | Classification |
| --- | ---: | ---: | ---: | ---: | --- |
| biased-self-verification:learner-22 | -13.762 pp | -14.468 pp | -14.468 pp/-14.468 pp | 0.000 pp/0.000 pp | question-evidence-path-implicated |
| noisy-history:learner-13 | -13.125 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| biased-self-verification:learner-23 | -8.487 pp | -13.845 pp | -12.419 pp/0.000 pp | -13.845 pp/-1.426 pp | mixed-selection-prior-path-interaction |
| ability-drift:learner-0 | -2.700 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| failed-write-retry:learner-31 | -2.617 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| changed-difficulty-distribution:learner-5 | -2.575 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| abandoned-session:learner-17 | -2.547 pp | -0.568 pp | —/— | —/— | stopping-implicated |
| abandoned-session:learner-6 | -2.451 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| changed-difficulty-distribution:learner-24 | -2.409 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| changed-difficulty-distribution:learner-17 | -2.257 pp | 0.706 pp | —/— | —/— | stopping-implicated |
| hard-history-easy-evaluation:learner-5 | -2.118 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| easy-history-hard-evaluation:learner-7 | -2.049 pp | 0.000 pp | —/— | —/— | stopping-implicated |
| changed-difficulty-distribution:learner-15 | -2.035 pp | 0.000 pp | —/— | —/— | stopping-implicated |

Eleven of thirteen material natural failures cease to be material at the common budget, which implicates stopping under the tested paths. Of the two biased-self-verification failures that persist, one is attributable to the changed question/evidence path under either common prior; the other implicates both the question/evidence path and prior sensitivity, with a path-dependent interaction.

Replay contrasts are conditional decompositions, not additive causal effects: the destination prior can change the final deck differently on the cold and warm evidence paths.

Next: test a predeclared current-document compatibility signal on a fresh development manifest before choosing a mitigation. Do not disable warm personalization, change the 0.90 weight, bind confirmation, or access the release holdout from this result.
