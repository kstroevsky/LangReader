# Vocabulary POS validation report v2

Status: completed adverse engineering evidence; representative release validation remains incomplete.

Frozen fixture: `ud-v2.18-pos-validation-v2`; SHA-256 `80dc8345871f55e0034432fbea1a1c2d4ef399c5af788c93fb0fea08908b19b5`. Runtime: Version 15.7.9 (Build 24G830).

The production 0.65 leading-probability and 0.20 margin thresholds were unchanged. No result in this report authorizes threshold tuning or a POS release claim.

## Overall

| Cases | Raw mapped-POS accuracy | Abstention | Final lexical-identity accuracy |
| ---: | ---: | ---: | ---: |
| 480 | 74.58% | 9.58% | 69.38% |

## Development and held-out results

| Cell | Cases | Raw POS | Abstention | Final identity |
| --- | ---: | ---: | ---: | ---: |
| en:development | 80 | 76.25% | 5.00% | 72.50% |
| en:heldout | 160 | 77.50% | 5.62% | 73.75% |
| de:development | 80 | 72.50% | 15.00% | 65.00% |
| de:heldout | 160 | 71.88% | 13.12% | 65.62% |

## Genre/source strata

| Genre/source | Cases | Raw POS | Abstention | Final identity |
| --- | ---: | ---: | ---: | ---: |
| answers | 61 | 77.05% | 3.28% | 72.13% |
| email | 45 | 80.00% | 4.44% | 75.56% |
| gsd-mixed-web | 240 | 72.08% | 13.75% | 65.42% |
| newsgroup | 45 | 75.56% | 11.11% | 68.89% |
| reviews | 45 | 77.78% | 4.44% | 77.78% |
| weblog | 44 | 75.00% | 4.55% | 72.73% |

## Split merge and downstream consequences

| Split/language | Missing gold identities | Extra predicted identities | Lemma POS-set mismatches | Denominator delta | Erroneous excluded/included mass | First question changed | Deck symmetric difference |
| --- | ---: | ---: | ---: | ---: | ---: | --- | ---: |
| development:de | 20 | 22 | 28 | -1 | 2/1 | yes | 44 |
| development:en | 16 | 17 | 19 | 1 | 1/2 | no | 33 |
| heldout:de | 38 | 42 | 53 | 3 | 1/4 | yes | 81 |
| heldout:en | 27 | 28 | 34 | -3 | 7/4 | no | 57 |

## Interpretation

The dev and held-out directions are similar, so this larger run confirms that the eight-token warning was not merely a micro-fixture artifact. The results are adverse: final identity remains materially below raw POS accuracy, German is weaker than English, two of four split/language cells change the first question, and every cell has many selected-deck identity differences.

This is still UD token/sentence evidence rather than representative private PDF/EPUB/DOCX documents or real learner evidence. English has five EWT genres; German GSD exposes one mixed-web source stratum. Upstream lemma limitations, OS-dependent NaturalLanguage behavior, target-token alignment, and corpus/domain coverage remain explicit limitations.
