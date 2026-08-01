# User-data backup and restore

`UserDataBackupService` is the core boundary for complete snapshots of
non-rebuildable Leaf Vocabulary data. It creates a directory package and can
validate or restore that package without depending on AppKit.

## Version 1 package

```text
snapshot.leafreaderbackup/
  manifest.json
  payload/
    preferences.plist
    word-records.sqlite3             # when present in the source profile
    personal-vocabulary.sqlite3      # when present in the source profile
    reading-notes.sqlite             # when present in the source profile
    ReadingNoteAssets/               # when present, including when empty
      ...
```

The manifest records the schema version, creation time, application and
preferences-domain identifiers, whether the managed note-assets directory is
present, and the kind, byte count, and SHA-256 digest of every payload file.

Included data:

* Word records and SRS state
* Personal-vocabulary profiles
* Reading notes and managed note images
* The complete preferences domain, including reader sessions, AI conversations,
  settings, and locally encrypted credential values

Excluded data is reconstructible or separately distributed: embeddings, cover
thumbnails, extracted EPUB/DOCX caches, dictionaries, speech models/runtimes,
audio caches, and SQLite WAL/SHM sidecars.

SQLite files are captured with the online-backup API. This produces a
transactionally consistent database snapshot even when the source database is
using WAL mode.

## Validation contract

Restore does not mutate the live profile until all of these checks pass:

* Schema version, app identifier, and preferences domain match
* Every relative path is safe, unique, and on the format's allow-list
* The assets-directory presence agrees with the manifest, including the empty
  directory case
* The payload contains exactly the listed regular files and no symbolic links
* Byte counts and SHA-256 digests match
* `preferences.plist` decodes to a dictionary
* Every SQLite snapshot returns `ok` from `PRAGMA integrity_check`

The digests detect accidental or post-capture modification; the package is not
cryptographically signed and should not be treated as an authenticated archive
from an untrusted sender.

## Restore contract

Restore first copies validated payload files into a same-volume staging
directory. It then moves each current managed unit into a rollback directory
and replaces it from staging. Preferences are applied last. If any replacement
or preference synchronization fails, applied units are reverted in reverse
order and the previous preferences domain is restored.

Production restore must run before shared SQLite store singletons are opened.
After a successful restore the app must terminate and relaunch: open SQLite
handles continue to refer to their previous file descriptors even after an
atomic path replacement. `UserDataRestoreResult.requiresRelaunch` makes this
requirement explicit.

Locally encrypted API keys derive their encryption key from the app bundle ID,
macOS user name, and home-directory path. They remain usable when restored to
the same account/profile; after a cross-account restore the user must enter the
keys again.

## Schema evolution

Version 1 rejects unknown schema versions. A future version must add an explicit
decoder/migration path and tests before accepting a new layout or managed data
kind. Do not silently reinterpret a version 1 package.
