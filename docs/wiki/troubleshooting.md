# Troubleshooting

Keywords: Sparkle, updates, GitHub Pages, TLS, signing, notarization, PDF paging, AI cache, network, wiki sync.

## Update Check Fails

- Confirm the appcast URL is reachable over HTTPS.
- Validate the appcast XML and its EdDSA signature.
- Confirm the installed app version is lower than the published version.
- Check that the download URL resolves to the signed installer.
- Inspect application logs before changing Sparkle configuration.

## Website TLS or Custom Domain Problems

- Confirm the repository Pages source and custom domain settings.
- Verify DNS records before requesting another certificate.
- Keep the `CNAME` file consistent with the configured domain.
- Allow DNS and certificate changes time to propagate.

## Installer Signing or Notarization Fails

- Verify the Developer ID Installer and Application identities are available.
- Check package and embedded app signatures independently.
- Confirm required entitlements and hardened runtime settings.
- Inspect the notarization log rather than retrying unchanged artifacts.
- Do not publish an appcast entry until the package passes Gatekeeper assessment.

## PDF Paging Feels Wrong

- Check whether single-page or two-page layout is active.
- Confirm whether cropped or original PDF bounds are selected.
- Ensure a text field is not consuming arrow keys.
- Reproduce with scroll paging and keyboard paging separately.
- Inspect debouncing if one gesture advances more than once.

## AI Analysis State Is Incorrect

- Confirm the current document identity matches the cached analysis data.
- Check embedding model and provider settings.
- Distinguish missing chunks from a fully rebuilt cache.
- Clear only the current book's cache before clearing all local analysis data.

## AI Requests or Network State Fail

- Verify the endpoint, model name, and API key.
- Check whether the provider requires a specific URL path or header.
- Test basic connectivity separately from model availability.
- Confirm cancellation and retry states are not leaving stale UI behind.

## Book or Vocabulary Data Looks Stale

- Reopen the document so location-based highlights are restored.
- Confirm the document identity and stored source path match.
- Check SQLite migrations and stored metadata before deleting user data.
- Back up the user profile before attempting manual repair.

## Wiki Sync Fails

- Run the local documentation build first.
- Regenerate Code Map and Type Index if required.
- Confirm the wiki remote exists and credentials permit pushing.
- Inspect generated changes before retrying `scripts/update_wiki.sh --push`.
