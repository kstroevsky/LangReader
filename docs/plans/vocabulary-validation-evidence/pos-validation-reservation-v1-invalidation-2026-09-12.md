# POS validation reservation v1 invalidation

The first scoring attempt for `ud-v2.18-validation-v1.json` aborted before a
report artifact was written. Case `de_gsd_test:test-s927:3` targets surface
`dem`, but that token is not present verbatim in the sentence's reconstructed
`# text`; the evaluator cannot locate a trustworthy range for NaturalLanguage.

No aggregate or case-result report was produced or inspected. Nevertheless, v1
is treated as consumed rather than silently repaired or relabeled untouched.
The replacement v2 selection must:

- require every target surface to occur exactly once verbatim in sentence text;
- exclude every v1 held-out case ID;
- use a new versioned SHA-256 selection order;
- remain frozen and unscored in a separate commit before evaluation.

This is a fixture-construction failure, not a POS accuracy result or a product
failure. The v1 fixture remains committed as provenance.
