# Vocabulary assessment diagnostic matrix

Matrix: `vocabulary-diagnostic-matrix-v1`; source: `e8411ceadfafd7cdf3372558292061eaf997d3b6`.

This is paired synthetic sensitivity evidence on development seeds only. It does not validate human calibration, select production parameters, or run the frozen release holdout.

| Factor | Tested subsystem | Origin evidence | Material metrics |
|---|---|---|---|
| evidence-reliability | observationModel | supported | responseNoiseCoverageBrier, responseNoiseCoverageECE, responseNoiseCoverageHitRate |
| epsilon-knowledge | latentKnowledgeModel | supported | itemResidualCoverageHitRate, thetaInterval90Coverage, wellSpecifiedCoverageECE |
| difficulty-prior-sd | latentKnowledgeModel | supported | itemResidualCoverageHitRate, thetaInterval90Coverage |
| coverage-quantile | coverageDeckDecision | supported | idiosyncraticCoverageHitRate, minimumDeckPrecision, responseNoiseCoverageHitRate |
| warm-prior-weight | warmPrior | inconclusive | warmStartCoverageHitDelta, warmStartQuestionReduction |

`supported` means the predeclared one-factor perturbation materially moved at least one mapped metric with a consistent direction for the same level across seeds. It does not prove that subsystem is the sole cause.

## Baseline failures retained

| Seed | Failures |
|---:|---|
| 10655832807036339045 | thetaInterval90Coverage, itemResidualCoverageHitRate, responseNoiseCoverageHitRate |
| 4839856769840061220 | wellSpecifiedCoverageHitRate, responseNoiseCoverageHitRate, idiosyncraticCoverageHitRate, warmStartCoverageHitDelta |
