Almost. I would **run this plan after three small amendments**. I re-checked the current branch, and PR #9 is still exactly at the planned baseline `b2b99696feda177be0699d5277a2c13c7c7c9bd5`, so `AUTH-003` is currently valid.

The architecture itself is ready. The fresh-reservation route is cleaner than rebinding v1, the 2A–2E strangler migration fixes the risky part of the earlier plan, cross-format ownership is now correct, the keyword lint is no longer brittle, and `GATE-009` no longer turns housekeeping into a scientific gate. I don't see a missing model/scientific concern.

I did find **one real execution blocker and two specification clarifications**.

### 1. Required: the historical Git-blob validator needs Git history in CI

`LOCK-003` now correctly says the old reservation validator should verify the generator bytes at the recorded historical Git revision.

That will work in a normal full local clone. But the Architecture workflow currently uses plain:

```yaml
- uses: actions/checkout@v4
```

which means the normal shallow checkout. The old commit `9df23ba...` will generally not be available to a validator doing something like:

```bash
git show 9df23ba...:scripts/evaluate_vocabulary_assessment.sh
```

The current workflow then runs `./scripts/check.sh --no-build`, so the new validator would make GitHub CI fail simply because the old object isn't present.

This needs an explicit clause, probably under `LOCK-003`, Commit 1, and `VER-003`:

> The deterministic CI checkout must make every historical revision required by a source lock available before `check.sh`. Prefer `actions/checkout` with `fetch-depth: 0`, or an equivalently deterministic explicit fetch of the locked revision. Missing historical Git objects are an infrastructure failure, not a generator-lock mismatch.

I would use:

```yaml
- uses: actions/checkout@v4
  with:
    fetch-depth: 0
```

for simplicity.

This is **not general CI repair**; it is a necessary prerequisite introduced by the new historical-validation architecture.

I also checked whether `reservationRevision = 9df23ba...` is actually a sensible historical source revision. It is: all four locked generator/ledger files have the **same Git blobs at `9df23ba` and at `b2b9969`**. So the historical-reference strategy itself is sound.

### 2. Required clarification: name the exact `source-lock.json`

The plan repeatedly refers to:

> `source-lock.json`

but there are already multiple source-lock-like files in the repository.

Most importantly, the obvious existing file:

```text
docs/plans/vocabulary-validation-evidence/verification/source-lock.json
```

is an older lock whose `source_revision` is `e8ea803...`; it locks the original authorized roadmap/ledger/acceptance files, not the current candidate plan, evidence register, review-readiness packet, etc.

So `AUTH-002` and `LOCK-006` are ambiguous as written.

If your plan-generation process has produced a **new companion source lock outside the pasted text**, that's fine—but the accepted plan should identify it exactly, for example:

```text
Candidate-plan source lock:
docs/plans/.../validation-boundary-source-lock-v1.json
SHA-256: ...
```

or, if it remains an external plan attachment:

```text
candidate source-lock attachment ID / filename / SHA-256
```

Do not leave it as a basename.

Otherwise an implementation agent could quite reasonably grab the old repository `verification/source-lock.json` and believe it is validating the new plan.

I would amend `AUTH-002` roughly to:

> The authoritative inputs for this extraction are enumerated in `<exact path or attachment identity>`, SHA-256 `<...>`. Other historical files named `source-lock.json` are not the extraction-plan source lock.

And `LOCK-006` should use that same exact identifier.

### 3. Small clarification: explicitly allow test-target → Validation dependencies

The intended architecture is clear:

```text
LeafReaderValidation → LeafReaderCore

LeafReaderApp -X→ LeafReaderValidation
LeafReaderCore -X→ LeafReaderValidation
```

But `OWN-007` also correctly says the App cross-format integration test may call a shared Validation comparison helper if useful.

For that to happen, `LeafReaderAppTests` would need:

```text
LeafReaderAppTests → LeafReaderValidation
```

That is perfectly healthy because it does not enter the shipping product closure.

`ARCH-002` says Validation→Core is the only allowed **production-code** dependency, so technically this is already consistent. But I would make it explicit so the architecture checker isn't accidentally written too broadly:

> Test targets may depend on `LeafReaderValidation` when testing validation-owned helpers. Such dependencies must not enter the `LeafReaderApp` product dependency closure. `LeafReaderValidation` itself must never depend on `LeafReaderApp`.

That's enough.

---

## One wording tweak I'd also make

`LOCK-003` asks for:

> a negative control for a corrupted historical blob

I would change that to:

> a negative control using mismatched historical bytes/checksum, path, or revision

You should not need to literally corrupt a Git object database to test this.

The validator can be dependency-injected or invoked against a synthetic mismatch and prove rejection.

That's cleaner and tests the same property.

---

# Everything else checks out

I double-checked the areas that worried me previously.

**The generator-lock problem is real and the plan now handles it correctly.** The current v1 reservation pins the evaluator shell, evaluator Swift source, causal-support source and canonical ledger by SHA-256; the current validator compares them against mutable working-tree paths. So migrating that validator before touching the pinned files is necessary, not bureaucracy.

**The manual-build problem is real and `LOCK-005` is necessary.** The current evaluator wrapper explicitly builds only `libLeafReaderCore.a`, then compiles the evaluator scripts using:

```text
-package-name LeafReader
-lLeafReaderCore
```

So a new SwiftPM Validation target would indeed be invisible to that runner until you add an analogous Validation-module/static-library build/link path.

**The diagnostic split is correctly targeted.** The existing Core diagnostics file really mixes production facts with A/B1/B2 generation/evaluation, fixed-bank counterfactuals and bank-specific errors. The 2B→2C→2D→2E sequence is much safer than trying to move it in one commit.

**The narrow snapshot is better now.** Dropping the full `DocumentVocabularyCandidate` and exposing only identity, mass, inclusion, evidence, response curve and production mask is the right direction. It makes the seam observational rather than an accidental second model API.

**The historical/fresh confirmation story is now very clean:**

```text
development-confirmation-v1
    old generator
    untouched
    never executed
    historical forever

extraction
    exact ordinary-development parity

development-confirmation-v2
    new generator
    fresh unseen seeds/documents
    future active reservation
```

I prefer this substantially to rebinding v1.

**The human-study ordering is now correct.** You can finish/stabilize only the relevant data-generating boundary and run an approved developmental study without waiting for unrelated POS/cross-format refactor housekeeping. At the same time, a path used by an active study can't be moved underneath the collection. That's the right balance.

**Commit 4 is now properly ownership-driven.** Real PDFKit/Web extraction remains an App integration test; Validation does not acquire a dependency on App merely to make the directory structure pretty.

**The migration controls terminate.** `MIG-001` is important. This prevents all the hash/parity transition machinery from becoming permanent architectural ceremony after the refactor is over.

---

## Is anything scientific missing?

I don't see anything new that needs to be added.

The remaining scientific path is still correctly:

```text
independent review
        ↓
two small human developmental studies
        ↓
human evidence decides warm strategy
        ↓
one frozen candidate
        ↓
fresh development confirmation
        ↓
release holdout
        ↓
real-learner validation
```

And the prohibited shortcuts remain correct.

I would especially **not** add any more synthetic experiment or methodological gate to this plan. At this point doing so would start recreating the complexity this extraction is intended to tame.

---

# My go/no-go

**GO, after these amendments:**

1. Make historical Git commits available to the Architecture CI checkout.
2. Identify the candidate extraction `source-lock` by exact path/attachment and hash.
3. Explicitly permit test-target → Validation dependencies while forbidding Validation → App and shipping-product reachability.
4. Optional wording cleanup: replace literal “corrupted Git blob” with an injected/mismatched historical-byte negative control.

Then I would accept this plan as the implementation base and execute it.

I would **not ask for another architectural planning round after that**. The remaining uncertainty is implementation/parity uncertainty, and the staged 2A–2E process is specifically designed to discover it safely.
