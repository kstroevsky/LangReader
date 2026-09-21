# Semantic verification — CI and source-lock revision

## Authority and delta

The immutable base is the verified but unaccepted candidate `base-plan.md`, SHA-256 `ee61a39745657e95dc6999bcda9bd15c0aa0b2d315221b65e8502be6b14fff9a`. The raw feedback is `feedback.md`, SHA-256 `0f821f7c73e566663cc1b0238bade196e4d9f38cc34f55144fcb8f13eb150fde`. The revised candidate is SHA-256 `55c2819200950f8c93a0d451bfe4659a4bc9bf5c0c1182086f28c89b95e8b879`. Conditional reviewer approval is not user acceptance.

All four closed delta items are implemented once: historical Git-object availability in Architecture CI; exact extraction-plan source-lock identity; test-only Validation dependencies; and injected historical-lock mismatch wording. The target ledger has 68 uniquely anchored requirements. Its nine changed requirement records are exactly the nine IDs authorized by the delta; every other base record is unchanged.

## Preservation and exact contracts

- The single production CAT, one-way production dependency, no Validation library product, Swift/Python ownership split, frozen evidence and old reservation, fresh post-extraction confirmation reservation, 2A–2E order, parity manifest, human-study boundary, performance gates, and eight scientific/release gates remain explicit and unchanged.
- The new CI clause changes no scientific threshold or reservation content. The Architecture workflow currently uses `actions/checkout@v4` without `fetch-depth`; it invokes `./scripts/check.sh --no-build`. The historical revision `9df23ba57477371dc99422725329c8cab0cb7bf6` exists locally, and its four locked generator/ledger blobs match the reservation hashes. The plan requires that object to be available in CI before validation and classifies absence as infrastructure failure.
- The exact extraction-plan companion is `docs/plans/vocabulary-validation-boundary/revision-2026-09-19-ci-source-lock/source-lock.json`, SHA-256 `12944c83d2bdf0423b89333457030140618c4c70ffd9e6909d4560cbc249e5ba`. This copy is byte-identical to the prior companion; the older vocabulary-evidence `verification/source-lock.json` has a different hash and is expressly not substituted.
- Test-target access to Validation is allowed only outside the shipping App product dependency closure. The forbidden production edges and Validation-to-App edge remain forbidden.

## Negative controls and cross-interface sequence

The historical validator's negative control is now an injected mismatch in bytes/checksum, path, or revision; the plan never asks to corrupt a Git object database. Its current-path-to-Git-blob migration remains before pinned generator edits. Commit 1 gains deterministic CI history availability before `check.sh`, while no fresh-reservation validator is required before a fresh reservation exists. A shallow checkout missing the historical object is repaired and rechecked before the source lock is interpreted; an unretrievable object stops the extraction as incomplete. No protected holdout or human collection is authorized by this plan edit.

## Mechanical and standalone result

`plan_guard.py` reports PASS: 7 changed sections, 0 added or removed, 62 active / 3 deferred / 3 superseded requirements, no errors or warnings. All 22 companion source-lock entries match current locked inputs. The candidate names its companion lock by full repository-relative path and hash, and distinguishes it from the older lock, so a new implementer can select the correct source bundle.

Independent forward-test: **PASS** on the candidate at SHA-256 `55c2819200950f8c93a0d451bfe4659a4bc9bf5c0c1182086f28c89b95e8b879`. No material unauthorized change, lost contract, cross-interface contradiction, or standalone gap was found. The candidate remains unaccepted until the user accepts it.
