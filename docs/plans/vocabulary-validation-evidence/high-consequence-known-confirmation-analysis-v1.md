# High-consequence known confirmation feasibility result

This is the single frozen fresh-seed development execution. It changes no production configuration and does not use the selected forensic cases as an acceptance set.

Retained rows: 1024; eligible: 1013; ineligible: 11.

| Arm | Mean warm-cold coverage | Worst warm-cold coverage | Material tails | Mean question reduction |
| --- | ---: | ---: | ---: | ---: |
| Production baseline | -0.1176 pp | -15.0491 pp | 40 | 72.503% |
| Independent occasion-1 confirmation | 0.0466 pp | -4.2226 pp | 32 | 62.596% |
| Fully correlated negative control | -0.1176 pp | -15.0491 pp | 40 | 62.596% |

The independent arm eliminated 8 baseline material tails and introduced 0. It requested 5.350 confirmations on average (median 5, p95 9, maximum 11); no row exceeded the 80-question ceiling.

It added 31 truly unknown cards (12017 occurrence mass) and 274 truly known cards (116304 occurrence mass) across eligible rows. These known-card additions are a precision/user-burden cost, not a benefit.

The material-tail gate failed; mean coverage passed; mean question reduction passed; question ceiling passed.

Decision: **reject-feasibility-candidate**. Do not tune the consequence rule or repeat-response semantics from this consumed result.

The independent arm is an optimistic synthetic bound and the fully correlated arm is a negative control. Neither establishes human repeat-response correlation, burden acceptability, or real-learner validity.
