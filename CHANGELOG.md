# Changelog

All notable changes to this package are documented here. This project adheres
to [Semantic Versioning](https://semver.org).

## 1.2.0

### Added

- **In-place COBS/R decoding**: `cobsrDecodeInPlace` and
  `cobsrDecodeInPlaceWithSentinel` decode the reduced codec within the caller's
  `Uint8List` and return the decoded length, needing no output buffer (COBS/R
  decoding never expands the data).

### Changed

- Added a dependency-free throughput benchmark
  (`benchmark/cobs_benchmark.dart`, excluded from the published package) that
  runs on every supported SDK.
- Extended the conformance test to also cover the configurable-sentinel and
  decode-error vectors from firechip/cobs-conformance.

## 1.1.0

### Added

- **Configurable sentinel byte** for both COBS and COBS/R: `cobsEncodeWithSentinel`
  / `cobsDecodeWithSentinel` and `cobsrEncodeWithSentinel` /
  `cobsrDecodeWithSentinel` encode to avoid an arbitrary delimiter byte instead
  of `0x00` (by XORing the finished encoding with the sentinel). `sentinel == 0`
  is byte-for-byte identical to the plain codecs.
- **In-place basic-COBS decoding**: `cobsDecodeInPlace` and
  `cobsDecodeInPlaceWithSentinel` decode within the caller's `Uint8List` and
  return the decoded length, needing no output buffer and with no "output too
  small" case (COBS decoding never expands).
- **Sentinel framing**: `cobsFrame`, `cobsUnframe`, `CobsFrameEncoder` and
  `CobsFrameDecoder` gain an optional `sentinel` parameter (defaulting to the
  `0x00` `cobsDelimiter`) so a non-zero byte can delimit frames on the wire, for
  both the basic and reduced codecs.

## 1.0.0

Initial release.

### Added

- **Basic COBS** encoding and decoding: the [cobs] codec plus the `cobsEncode`
  and `cobsDecode` functions.
- **COBS/R (Reduced)** encoding and decoding: the `cobsr` codec plus the
  `cobsrEncode` and `cobsrDecode` functions. COBS/R often removes the trailing
  overhead byte for smaller messages.
- **`dart:convert` integration**: `CobsCodec` / `CobsrCodec` extend `Codec`, and
  the encoders/decoders extend `Converter` with chunked-conversion support, so
  they compose with `fuse`, `Stream.transform`, and other codecs.
- **Stream framing** for `0x00`-delimited links (serial, UART, USB-CDC):
  `cobsFrame`, `cobsUnframe`, and the `CobsFrameEncoder` / `CobsFrameDecoder`
  stream transformers. `CobsFrameDecoder` reassembles packets across arbitrary
  chunk boundaries, propagates pause/resume/cancel to the source (even during a
  delimiter-less run), supports a `maxFrameLength` bound against unbounded
  buffering on a noisy or malicious link, and offers configurable handling of
  empty and malformed frames.
- **Size helpers**: `encodingOverhead` and `maxEncodedLength` for buffer
  pre-allocation.
- Extensive test suite, including the golden vectors from the reference COBS and
  COBS/R implementations.

[cobs]: https://pub.dev/documentation/cobs_codec/latest/cobs_codec/cobs-constant.html
