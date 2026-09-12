# Vocabulary POS fixture attribution

The selected token/sentence excerpts in `ud-v2.18-selected.json` come from Universal Dependencies release 2.18 (2026-05-15).

- English EWT, tag `r2.18`, commit `b7711cce01cdd4f5fcc0a8199b8a50d951b16c0c`, test-file SHA-256 `fa024f43dc5da3c5ac02563bc9bd0e974f46cbb1560823976a8f342a37dc494a`. Upstream license: CC BY-SA 4.0.
- German GSD, tag `r2.18`, commit `81d8c3612a88f5867fd089e9c0a5466ef230078b`, test-file SHA-256 `595070aa50b706a91dc66f17c296f7a9a25cbc75269f177c27680fb1c21528ab`. Its annotations are CC BY-SA 4.0; underlying sentence text is distributed under the additional terms in the upstream `LICENSE.txt` and carries no warranty.

The fixture preserves upstream sentence IDs, token IDs, UPOS/XPOS, morphological features, and immutable source hashes. It is a small engineering diagnostic, not a representative corpus or a claim that German GSD's automatically assigned lemmas are unquestionable sense/lemma ground truth.

`ud-v2.18-validation-v1.json` additionally freezes deterministic samples from
the same repositories' dev and test files. English EWT dev SHA-256 is
`39239e0a60db3ae68f4b7036189f11b6692741d10ff8240dd91f74f2760d90f8`;
German GSD dev SHA-256 is
`01e8e674973592747ffe9a8c77fcf9d2f5936a8484e731ad4f76254318a8952c`.
The test-file hashes and license/underlying-text qualifications above are
unchanged. The dev sample is for development diagnosis; the separately sourced
test sample is held out until its frozen scoring step. German GSD exposes one
declared mixed-web corpus stratum rather than multiple reliable genre labels,
which remains a reporting limitation.
