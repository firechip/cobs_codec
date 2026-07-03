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

## Commits and pull requests

- Write clear, imperative commit messages (e.g. "Fix decoder backpressure on
  delimiter-less runs").
- Commits and tags in this repository are **SSH-signed**; please sign your
  commits (`git config gpg.format ssh` and set `user.signingkey`) and include a
  sign-off (`git commit -s`) certifying the [DCO](https://developercertificate.org/).
- Keep pull requests focused; update `CHANGELOG.md` under an `## Unreleased`
  heading for user-visible changes.

## Reporting bugs

Open an issue at <https://github.com/firechip/cobs_codec/issues> with a minimal
reproduction: the input bytes, what you expected, and what you got.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](LICENSE).
