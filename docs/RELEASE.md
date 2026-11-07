# Release process

ExtendPad releases contain the Mac apps and Android receiver. Releases are
built from `release/<version>` branches and promoted to `main` only after the
required verification and publication gates.

## Versioning

`version.txt`, `.release-please-manifest.json` and `CHANGELOG.md` must agree
with the release branch. Git tags use `vX.Y.Z`; existing tags are never moved.

Android version codes increase monotonically. Mac marketing and build versions
come from the release configuration. Local builds default to `0.0.0` and are
not publication artifacts.

## Candidate pipeline

Every push to `release/<version>` runs `.github/workflows/release-candidate.yml`:

1. `plan` validates the branch, version and absence of an existing tag, then
   records the exact candidate commit.
2. `mac` builds, signs, notarizes and verifies the sender and receiver DMGs and
   their update feeds.
3. `android` runs tests and lint, builds and signs the release bundle, and
   uploads it to the configured testing track.
4. `summary` reports readiness without publishing.

A newer push cancels the older candidate run. Build and upload jobs do not
create GitHub releases or tags.

## Credentials and environments

Release credentials exist only in their intended protected GitHub
environments. The workflows use pinned actions and environment checks before
accessing secrets. Never copy signing or store credentials to repository-level
secrets for convenience.

Use `scripts/release/release-secrets.rb status` for a non-disclosing status
check. `apply-environments.sh` and `apply-rulesets.sh` require explicit
`--apply` and repository administration rights.

Android production requires a production review track and the separate,
per-version `ANDROID_PRODUCTION_AUTHORIZED` value. Testing tracks are not
counted as public availability.

## Publication

`release-publish.yml` is dispatch-only and runs from the matching release
branch at the reviewed candidate commit. Its ordered stages are:

1. Verify the candidate and required store state.
2. Verify the exact Mac artifacts and feeds, create and validate the release,
   then make it Latest.
3. Complete authorized Android publication. Managed publishing may require an
   explicit Play Console Publish action.
4. Publish the website manifest with only platforms confirmed live.
5. Propose promotion of the released source to `main`.
6. Record published or pending state without hiding unfinished work.

A resume requires the same publication approval and revalidates the live
release, artifact hashes and store state. Mac feed verification failure restores
the previous Latest release rather than leaving a partial update visible.

## Local verification

```sh
ruby scripts/release/check-release-workflows.rb
ruby -Iscripts/release/lib -e \
  'Dir["scripts/release/test/*_test.rb"].sort.each { |f| require File.expand_path(f) }'
```

Also run the Mac and Android tests and inspect physical-device behavior where
possible. Do not describe source inspection, automated tests, emulator tests
and physical QA as interchangeable.

## Branch rules

See [BRANCHING.md](BRANCHING.md). Development targets `dev`; release fixes go
to the release branch and are merged back. Published tags and release assets
are immutable compatibility contracts.
