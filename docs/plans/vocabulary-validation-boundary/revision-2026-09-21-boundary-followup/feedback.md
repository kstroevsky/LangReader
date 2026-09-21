# Review feedback and scope decision

The user reviewed committed extraction head `5de7128feb8bc2cab2457d88d0fd7d88671654d9` and identified three follow-ups before closing the structural extraction:

1. The derived evidence-status register indexes only v1 although the v2 manifest and `CURRENT.md` identify v2 as the active future reservation. Retain v1 as historical/unexecuted, add v2 as active/unexecuted, index the structural extraction checkpoint and source lock without elevating scientific status, refresh the reviewed head, and leave scientific statuses unchanged.
2. `AdaptiveVocabularyAssessment` still exposes `nextQuestionForDiagnosticContinuation()`, `diagnosticNaturalStopReason`, `diagnosticKnownProbability(for:)`, and `result(selectionOverride:)`. Remove the latter three where possible by using production results or immutable observations. For continuation, the user prefers explicitly allowing exactly one narrow package-scoped continuation primitive over an elaborate workaround. Do not leave the AC-003 contradiction undocumented.
3. The v2 validator checks only two named development seeds, not all prior development/release sets. Derive/check prior identities from versioned sources; document the opaque-document namespace distinction.

The user said not to rewrite the already-created commit history. The remote Architecture run is red on a German participle assertion also reported failing at the pre-extraction baseline; that CI defect is separate from these extraction follow-ups.

Codex then asked: “May I preserve v2 unchanged as historical and seal a new, disjoint v3 reservation after the Core change?” The user replied: “Continue”. This is the authorization for the v2→v3 follow-up route, not for outcome access, candidate freeze, release-holdout access, or a model-policy change.
