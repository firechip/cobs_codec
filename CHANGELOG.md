# Changelog

All notable changes to this package are documented here. This project adheres
to [Semantic Versioning](https://semver.org).

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
