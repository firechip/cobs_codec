# Contributing to cobs_codec

Thanks for your interest in improving `cobs_codec`! This document explains how to
build, test, and submit changes.

## Code of conduct

Be respectful and constructive. By participating you agree to keep discussions
professional and welcoming.

## Getting started

You need the [Dart SDK](https://dart.dev/get-dart) `>= 3.5.0` (the package is
pure Dart and works with Flutter too).

```console
git clone https://github.com/firechip/cobs_codec.git
cd cobs_codec
dart pub get
```

## Development workflow

Before opening a pull request, make sure all of the following pass — this is the
exact bar CI and `pub.dev` enforce:

```console
dart format .                 # formatting (must produce no changes)
dart analyze                  # static analysis (must report no issues)
dart test                     # unit tests (must be all green)
dart run example/cobs_codec_example.dart   # example still runs
```

For a release-readiness check, run the pub scorer:

```console
dart pub global activate pana
dart pub global run pana --no-warning .
```

The package targets a perfect **160/160** pana score; please don't regress it.

## Correctness bar

COBS and COBS/R are exact, well-specified algorithms, so correctness is
non-negotiable:

- Any change to `lib/src/cobs.dart` or `lib/src/cobsr.dart` must keep the golden
  vectors in `test/` passing. Those vectors are ported from the reference
  implementations and must **not** be changed to make new code pass.
- New behaviour needs new tests. For encode/decode changes, add a golden vector;
  for streaming/framing changes, add a test under `test/framing_test.dart`.
- The implementation is validated by differential testing against the original
  Python reference (`cobs-python`). If you change the algorithms, run a
  byte-for-byte comparison against that reference before submitting.

## Style

- Follow the analyzer/`dart format` output — no manual style debates.
- Every public API member must have a dartdoc comment
  (`public_member_api_docs` is enforced).
- Keep the public surface minimal; add internal code under `lib/src/` and export
  deliberately from `lib/cobs_codec.dart`.

## Git workflow: Trunk-Based Development with tbdflow

This project uses [Trunk-Based Development](https://trunkbaseddevelopment.com/):
small, frequent changes integrated into `main` (the trunk) rather than
long-lived branches. We use the [`tbdflow`](https://github.com/cladam/tbdflow)
CLI (`cargo install tbdflow`) so the safe path is the easy path.

`tbdflow commit` pulls `main`, creates a Conventional Commit, and pushes:

```console
tbdflow commit --type fix --scope decoder -m "handle backpressure on idle links"
```

For a change that needs review, use a short-lived branch and merge it back
quickly: `tbdflow branch --type feat --name my-change`, then `tbdflow complete`.
Other helpers: `tbdflow sync`, `tbdflow radar`, `tbdflow changelog`,
`tbdflow undo`.

Two committed files drive this workflow:

- **`.tbdflow.yml`** -- workflow + commit-message lint rules (trunk branch,
  allowed Conventional Commit types, lowercase scope/subject, 72-char subject).
- **`.dod.yml`** -- the Definition of Done checklist shown before each commit
  (format, analyze, test, changelog, conformance). Bypass for a trivial change
  with `--no-verify`.

Commits and tags are **SSH-signed** (`tbdflow commit` respects the repo's
signing config); include a sign-off (`-s`) certifying the
[DCO](https://developercertificate.org/). Keep pull requests focused and update
`CHANGELOG.md` under an `## Unreleased` heading for user-visible changes.

## Conventional Commits

Every commit message follows
[Conventional Commits](https://www.conventionalcommits.org):
`type(scope): short imperative subject`. Allowed **types**: `build`, `chore`,
`ci`, `docs`, `feat`, `fix`, `perf`, `refactor`, `revert`, `style`, `test`. The
subject is lowercase, imperative, and has no trailing period; breaking changes
use `!` (`feat!:`) or a `BREAKING CHANGE:` footer.

This is enforced locally by `tbdflow commit` and in CI by the **Commit lint**
workflow (`.github/workflows/commit-lint.yml`), which checks every commit in a
pull request.

## Reporting bugs

Open an issue at <https://github.com/firechip/cobs_codec/issues> with a minimal
reproduction: the input bytes, what you expected, and what you got.

## Releasing

Publishing to pub.dev is automated from a signed `v*` tag, but the **GitHub
Release is created by hand — don't skip it.** The full checklist:

1. Bump `version` in [`pubspec.yaml`](pubspec.yaml) and add a `## X.Y.Z` section
   to [`CHANGELOG.md`](CHANGELOG.md). Validate with `dart pub publish --dry-run`.
2. Commit (`chore: release X.Y.Z`) and tag it **signed**:
   `git tag -s vX.Y.Z -m "cobs_codec X.Y.Z"`; push `main` and the tag.
3. The tag triggers [`publish.yml`](.github/workflows/publish.yml), which
   publishes to **pub.dev** via automated publishing (OIDC) — no credentials.
4. Create the **GitHub Release** and attach the exact published archive:

   ```console
   curl -fsSL https://pub.dev/api/archives/cobs_codec-X.Y.Z.tar.gz \
     -o cobs_codec-X.Y.Z.tar.gz
   gh release create vX.Y.Z --verify-tag --title "cobs_codec X.Y.Z" \
     --notes-file notes.md cobs_codec-X.Y.Z.tar.gz
   ```

   The description should mirror the pub.dev release: the `CHANGELOG.md`
   highlights, an install snippet, and the
   `pub.dev/packages/cobs_codec/versions/X.Y.Z` link.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
