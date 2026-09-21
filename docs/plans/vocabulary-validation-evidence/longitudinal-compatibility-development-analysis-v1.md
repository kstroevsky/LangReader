# Vocabulary warm compatibility development result

This is the single frozen development execution. It changes no production configuration and does not access development-confirmation or release-holdout data.

Retained rows: 1024; eligible: 1020; ineligible: 4.

| Policy | Mean warm-cold coverage | Worst warm-cold coverage | Material tails | Mean question reduction |
| --- | ---: | ---: | ---: | ---: |
| Production count-only relaxation | -0.1830 pp | -15.9906 pp | 55 | 72.019% |
| Frozen likelihood-ratio candidate | -0.1391 pp | -15.9906 pp | 54 | 68.934% |

The signal supported relaxation for 721 eligible rows, rejected it for 284, had insufficient validation support for 15, and applied the 20-question counterfactual to 242 rows.

It eliminated 4 previous material tails and introduced 3. The predeclared material-tail gate failed; the mean-coverage gate passed; the question-reduction gate passed.

Decision: **reject-candidate-retain-production**. The zero threshold must not be tuned from this consumed result.

Synthetic deterministic learner draws and a conditional warm-selected validation signal do not establish real-learner safety or confirmatory non-inferiority.
