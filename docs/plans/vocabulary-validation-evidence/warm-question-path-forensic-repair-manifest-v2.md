# Warm question-path forensic repair manifest v2

Status: **frozen, not executed**.

Attempt v1 completed with exact path parity but could not calculate final-deck
symmetric-difference occurrence mass because it omitted unasked final inventory
rows. This repair keeps the same 11 selected run IDs, paths, hidden truths,
responses, question traces, and frozen summary definitions.

The only permitted new evidence is one final row per inventory item and traced
path containing identity, occurrence mass, hidden truth, learner exception,
asked/evidence state, final known probability/classification, and final deck
selection. Existing path metrics and v1 question traces must match byte-for-byte
after decoding.

The repaired analysis remains an outcome-biased mechanism study. It may report
supported and falsified hypotheses, but it cannot estimate failure prevalence,
select a threshold, choose or activate a production change, bind confirmation,
access the release holdout, reuse POS held-out data, inspect private GUI files,
or touch user databases.
