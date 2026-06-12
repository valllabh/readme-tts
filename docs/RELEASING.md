# Releasing

Release management runs through GitHub Releases. Sparkle reads appcast.xml
from the main branch and downloads the release zip from the matching GitHub
release, verifying its EdDSA signature against the public key in Info.plist.

## One time setup

- `gh auth login` with push access to the repo
- `make sparkle-keys` generates the EdDSA key pair in the login keychain.
  The private key never leaves the keychain and is never committed. The
  printed public key must match SUPublicEDKey in Bundle/Info.plist.
- Signing: the Makefile signs with the local "ReadMe Dev Signing" certificate
  and falls back to ad hoc. A Developer ID certificate plus notarization will
  slot into the same place later; nothing about it lives in the repo.

## Cutting a release

```sh
git tag v0.2.0
make publish
```

`make publish` runs the chain:

1. `bundle` builds the signed .app; CFBundleShortVersionString comes from the
   tag, CFBundleVersion is the commit count (monotonic, what Sparkle compares)
2. `dist` zips the app into dist/ReadMe-<version>.zip
3. `appcast` runs Sparkle generate_appcast, which signs the zip with the
   keychain key and writes appcast.xml with download URLs pointing at the
   GitHub release for the tag
4. creates the GitHub release with the zip attached, commits appcast.xml,
   and pushes

Installed apps see the update on their next Sparkle check (automatic, or
About panel, Check for Updates).

## Notes

- Tag before publishing; an untagged HEAD falls back to version 0.1.0.
- dist/ is gitignored; appcast.xml is committed, that is the feed.
- Until a Developer ID certificate is in place, updates carry an ad hoc or
  local signature, so macOS re-asks for the Accessibility permission after
  an update. The app resets its stale permission row itself on launch.
