Yes. I think this is a **very strong plan and substantially more mature than the earlier architectural sketch**.

I would accept it as the implementation base after a few targeted changes. The core architecture is right, the scientific boundaries are unusually well protected, and—importantly—the plan understands that this is a **behavior-preserving extraction**, not another opportunity to redesign vocabulary assessment.

I checked the current `b2b9969` structure while reviewing it. Two of the plan's trickiest premises are real rather than hypothetical. The development-confirmation reservation really does pin the exact SHA-256 of the evaluator shell, evaluator Swift file, causal-support Swift file, and canonical ledger; it remains unexecuted. [Reservation at `b2b9969`](https://github.com/kstroevsky/LangReader/blob/b2b99696feda177be0699d5277a2c13c7c7c9bd5/docs/plans/vocabulary-validation-evidence/development-confirmation-reservation-v1.json) And the evaluator wrapper really does manually compile the Swift scripts with `swiftc`, `-package-name LeafReader`, and only `libLeafReaderCore.a`; adding a SwiftPM target by itself will therefore not magically make the new validation module available to that runner. [Evaluator wrapper at `b2b9969`](https://github.com/kstroevsky/LangReader/blob/b2b99696feda177be0699d5277a2c13c7c7c9bd5/scripts/evaluate_vocabulary_assessment.sh)

The other important premise is also correct: `VocabularyAssessmentCausalDiagnostics.swift` currently mixes two different ownership classes. It contains genuine production observations—the snapshot, posterior, production masks, production selection—but also A/B1/B2 bank definitions, independent random-bank generation, fixed-bank evaluation, counterfactual selected sets, and bank-specific errors. So the proposed split is not architectural theater; there is a real boundary to extract.

### My assessment

| Part                                                   | Assessment                                                           |
| ------------------------------------------------------ | -------------------------------------------------------------------- |
| Goal                                                   | **Worth doing**                                                      |
| `LeafReaderValidation → LeafReaderCore` boundary       | **Correct**                                                          |
| No separate package/repository                         | **Correct**                                                          |
| No library product / no App dependency                 | **Correct**                                                          |
| Keep one production CAT implementation                 | **Critical and correct**                                             |
| Move study schemas to Validation                       | **Correct**                                                          |
| Keep product research export/audit in Core for now     | **Correct**                                                          |
| Preserve Python statistical role                       | **Correct**                                                          |
| Historical evidence immutability                       | **Excellent**                                                        |
| Baseline/output parity                                 | **Excellent**                                                        |
| Sealed-generator handling                              | **Scientifically excellent, operationally a little overcomplicated** |
| Five-commit implementation sequence                    | **Good idea, but Commit 2 is too large**                             |
| Architecture lint                                      | **Right idea, one part is too brittle**                              |
| Requiring the *entire* extraction before human studies | **I would relax this**                                               |

The biggest positive change from our earlier discussion is the treatment of the sealed confirmation reservation. Your plan noticed a non-obvious problem that could easily have invalidated the whole exercise: moving code while keeping output identical is **not sufficient** when a scientific reservation explicitly defines the generator by source-file hashes. That is exactly the sort of thing people accidentally hand-wave during refactors.

## I would make five changes before accepting it

1. **Prefer a fresh post-extraction development-confirmation reservation rather than rebinding the existing reserved seeds.** Keep the existing reservation forever as `reservedNotExecuted` historical evidence. After the extraction is complete and parity is established, reserve a fresh disjoint seed/document set against the extracted generator before any future candidate is frozen.

   Your plan currently correctly allows either route under `LOCK-002`. I would choose the fresh-reservation route now rather than carrying both possibilities throughout implementation.

   There is little upside to preserving those particular unseen seeds. They have never been inspected. A fresh reservation gives you a much cleaner story:

   ```text
   development-confirmation-v1
       old generator
       never executed
       preserved forever

   development-confirmation-v2
       post-extraction generator
       fresh unseen seeds/documents
       active future reservation
   ```

   You still need to modify the historical validator so it validates v1 against the recorded Git revision rather than requiring the old source files to remain current. But you avoid the more philosophically awkward question of whether an unseen set tied to generator A can be “rebound” to generator B merely because development-fixture outputs appear identical.

   This is cleaner scientifically and simpler operationally.

2. **Break the current Commit 2 into a strangler-style migration rather than changing ownership, APIs and runner linkage simultaneously.** The proposed Commit 2 moves study schemas, splits the diagnostics file, removes `selectionOverride`, changes errors, and changes the manually built runner linkage. That's too much for the highest-risk commit.

   I would instead do:

   ```text
   2A — move the independent study schemas/tests
   2B — introduce the narrowed Core observation snapshot
        and new Validation evaluator alongside the old evaluator
   2C — prove old-vs-new A/B1/B2 + counterfactual parity
   2D — switch evaluator wrapper/build linkage to Validation
   2E — remove the old Core experiment implementation
   ```

   Temporary duplication of **validation-only evaluator code** during 2B–2D is acceptable. Duplication of the production CAT is not.

   This gives you something extremely useful: for one commit, you can execute the *old implementation and new implementation in the same source tree* against identical snapshots and prove exact parity before deleting the old one.

3. **Narrow the Core snapshot one step further than the current implementation.** Today its `Item` stores a full `DocumentVocabularyCandidate`. The plan says “frozen item identity and occurrence mass,” which is better.

   I would follow the plan literally and expose only the fields validation actually needs, such as:

   ```text
   canonicalKey
   occurrenceCount
   isIncluded
   evidence
   responseCurve
   productionKnownMask
   ```

   rather than carrying the entire production candidate object through the observation seam.

   Similarly, keep posterior/epsilon/reliability/theta positions private where possible and expose narrow snapshot operations or immutable values intentionally needed by Validation.

   The Core seam should answer:

   > What happened in production?

   not:

   > Here is enough of Core's internals to build arbitrary alternate assessment implementations.

4. **Treat the keyword part of `VER-002` as a lint, not the main architectural guarantee.** Parsing the SwiftPM dependency graph and prohibiting `Core/App → Validation` is strong. Checking source imports is strong.

   But rules such as “fail if the phrase `holdout` or `synthetic truth` appears anywhere in package APIs” can become brittle. Comments, unrelated future features, or legitimate diagnostic terminology can create false positives.

   I would make the hard enforcement:

   ```text
   target dependency graph
   imports
   shipping product link closure
   explicitly forbidden validation types/modules
   ```

   and make the broader vocabulary/name scan either narrowly scoped to declarations or an advisory lint with an explicit allowlist.

5. **Change `GATE-009` so human studies depend on stabilization of the study execution boundary, not completion of every housekeeping extraction.** Right now:

   > the structural extraction must finish before any human study

   effectively creates a new scientific gate.

   I agree that you should not start human collection while the relevant executable path is being moved. But moving reusable POS and cross-format helper code into `LeafReaderValidation` is not intrinsically necessary before running a pretest-interference study.

   I would require before human collection:

   ```text
   Core/Validation dependency boundary finalized
   relevant assessment/study schemas finalized
   study execution path parity-verified
   current executable/version hashes frozen
   independent review approved
   ```

   But if some unrelated POS fixture helper still lives in its old test file, that should not block a properly approved human experiment.

   In other words, **freeze what generates or interprets the human-study data**, not every validation housekeeping task.

Those are the only material changes I would make.

## One wording inconsistency worth fixing

`OWN-003` says validation manifests, reports and “reservation-aware runner mechanics” belong to `LeafReaderValidation`, while `OWN-006` correctly says Python orchestration/statistical tooling stays where it is.

I would rewrite `OWN-003` to say those concepts belong to the **validation subsystem**, and that their Swift execution portions move to `LeafReaderValidation` while Python orchestration may remain under `scripts/`.

Otherwise an implementer could reasonably interpret `OWN-003` as “rewrite reservation machinery in Swift,” which you explicitly do not want.

## The target itself is appropriate

One concern I had before reading the detailed plan was whether adding a Swift target would simply move clutter around. Looking at the current repository makes me more comfortable with it.

`Package.swift` currently has exactly the straightforward structure we discussed: production `LeafReaderCore`, shipping `LeafReaderApp`, and their test targets. [Current `Package.swift`](https://github.com/kstroevsky/LangReader/blob/b2b99696feda177be0699d5277a2c13c7c7c9bd5/Package.swift)

Adding:

```text
LeafReaderValidation → LeafReaderCore
LeafReaderValidationTests → LeafReaderValidation + LeafReaderCore
```

without exposing a product keeps the shipping architecture conceptually unchanged.

And `swift build` of the app product doesn't need Validation in its dependency closure.

So this does **not** turn LangReader into a framework zoo.

## `OWN-009` is particularly good

Removing:

```text
diagnosticSnapshot(selectionOverride: ...)
```

from Core is exactly the sort of cleanup this refactor should achieve.

Production should say:

> Here is the selection production actually made.

Validation should say:

> What would this already-observed state have looked like if we evaluated another selected set?

That seemingly small distinction is the architectural philosophy of the whole extraction.

Likewise splitting `VocabularyDiagnosticInputError` is correct. `invalidPosterior` is plausibly an observation-construction concern; `incompatibleB1SampleCount` clearly has no business being a Core concept.

## Moving the study schemas is also appropriate

The current `VocabularyValidationStudyPackageV2` is explicitly a fabricated/research package: participants, study documents, criterion records, retest manifests, inclusion probabilities, analysis splits, sampling manifests, and `realCollectionAuthorized == false`.

That is exactly the kind of type whose presence in `LeafReaderCore` now makes Core look conceptually larger than the product really is.

Moving those types to Validation while retaining Core-owned types such as `VocabularyLexicalItemID`, `VocabularyKnowledgeEvidence`, and production classifications as dependencies is a clean direction:

```text
Validation study schema
       ↓ uses
production vocabulary concepts
```

not vice versa.

## The parity contract is stronger than I would normally demand—and here that's appropriate

For a normal refactor, byte-identical Markdown is excessive.

For this repository, it makes sense because you have deterministic scientific artifacts, frozen failed candidates, reservations and source provenance.

I particularly agree with the rule that you cannot “fix” a parity failure by updating the golden/schema. That would defeat the purpose of the extraction.

I would add one small implementation artifact:

> Create a **frozen extraction-parity manifest before editing**.

It should enumerate the exact baseline commands, inputs, expected exit statuses, artifact paths/hashes and predeclared canonicalization fields.

You already describe all of this in the baseline checkpoint; making it one machine-readable manifest would prevent the parity suite itself from drifting during implementation.

That would be useful governance rather than another elaborate framework because it exists only for this finite migration.

## One thing I would not move merely for symmetry

The cross-format App fixture currently exercises real PDF/EPUB/DOCX extraction and then the final vocabulary pipeline. Some of that test legitimately belongs in the App test layer because format extraction is platform/application integration behavior.

So I would interpret Commit 4 carefully:

> move **reusable evaluation mechanics** into Validation where possible, but leave App integration tests in `LeafReaderAppTests` when they exercise PDFKit/Web/document-loading seams.

Don't make `LeafReaderValidation` depend on `LeafReaderApp` merely to claim that all validation code has moved.

The desired dependency graph matters more than directory purity.

POS evaluation based entirely on Core + NaturalLanguage-compatible helpers may be extractable. Cross-format application integration may intentionally remain an App test that calls shared Validation comparison utilities only where practical.

That's another place where I would prioritize ownership over symmetry.

## Does this plan itself risk becoming another overcomplicated process?

A little—but I think it stays on the correct side of the line if you make the changes above.

The lengthy `LOCK-*` section is not accidental bureaucracy. Your current reservation genuinely pins the exact files you propose to change. The complexity already exists; the plan is making it explicit.

After this extraction is finished, though, I would expect the ongoing architecture to become **simpler**, not keep these migration rules forever.

The end state should feel like:

```text
Production
    LeafReaderCore
    LeafReaderApp

Correctness
    CoreTests
    AppTests

Validation software
    LeafReaderValidation
    ValidationTests
    thin scripts + Python analysis

Historical evidence
    immutable docs/perf + evidence archive

Current state
    one short CURRENT.md
```

The `LOCK-001…006`, migration parity manifest and source-transition machinery are **temporary migration controls**, not permanent architecture.

That's important.

### Bottom line

I would approve this plan after the five amendments above.

The plan gets the fundamental things right:

* it solves a real ownership problem;
* it creates exactly one new internal target;
* production cannot depend back on it;
* it doesn't invent a generic framework;
* it doesn't rewrite Python unnecessarily;
* it retains normal correctness tests with their owners;
* it preserves historical evidence rather than “cleaning” it;
* it recognizes the sealed-generator source-identity problem;
* it requires exact behavioral parity;
* it stops after extraction rather than immediately generalizing.

My strongest recommendation is to **choose the fresh post-extraction confirmation reservation route upfront** and make the high-risk diagnostic migration more incremental. With those changes, this is not just a reasonable refactor plan; it is a very good way to reduce the complexity we accumulated without weakening the evidence discipline that created it.
