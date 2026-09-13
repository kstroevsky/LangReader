# Warm question-path forensic repair manifest v2

Status: **consumed; repair complete**.

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

The single repaired run completed from clean revision `fada508`. All 11 case
identities, original path metrics, and question traces match v1. The final rows
conserve assessable and missed occurrence mass. Across the seven selected severe
warm-natural paths, 5,518 of 6,200 missed occurrence mass (89%) belonged to
asked truly unknown items carrying known-supporting evidence; only 682 (11%) was
never asked. See the [frozen analysis](warm-question-path-forensic-analysis-v2.md).
