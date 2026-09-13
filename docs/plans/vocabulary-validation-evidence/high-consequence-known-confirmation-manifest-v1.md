# High-consequence known confirmation feasibility manifest v1

Status: **frozen, not executed**.

The selected-case forensics found that 89% of severe warm missed occurrence
mass came from asked, truly unknown items carrying known-supporting evidence.
This reservation tests one direct but still diagnostic safeguard on a fresh
seed. It does not change production behavior.

An answered known-supporting item is “high consequence” only when its occurrence
count alone exceeds the document's complete miss-mass budget:

`floor((1 - targetCoverage) * assessableOccurrenceMass)`.

Such an item receives one additional confirmation after the natural path and
before deck publication. The production deck remains intact. The item is added
only if confirmation is missing, excluded, or does not support known. Posterior,
theta, original question selection, stopping, and the 0.90 prior weight are not
changed.

Two frozen arms prevent an unjustified independence assumption:

- an optimistic arm uses an independent deterministic occasion-1 response from
  the existing synthetic response model;
- a fully correlated negative control repeats the original evidence.

The fresh run uses eight eligible-history scenarios, 128 learners each, and
retains all 1,024 rows including naturally ineligible histories. The independent
arm must have zero losses worse than two percentage points, mean coverage change
of at least -0.5 points, and mean question reduction of at least 50%. Confirmation
counts and added truly-known card count/mass are mandatory outputs, but no UX
cost threshold is invented here.

Even a passing independent arm cannot authorize production: repeat-response
correlation, burden acceptability, and real-learner coverage/precision remain
external evidence requirements. Failure consumes the reservation and cannot be
used to tune the occurrence rule or confirmation semantics.
