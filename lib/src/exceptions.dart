// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Exception types thrown by the `cobs_codec` package.
library;

/// Thrown when decoding fails because the input is not a valid COBS (or COBS/R)
/// encoded byte sequence.
///
/// A valid COBS stream never contains a zero byte, and every length code must
/// point to a valid position within the input. Decoding raises this exception
/// when either invariant is violated:
///
/// * a zero (`0x00`) byte appears in the input, or
/// * a length code claims more bytes than remain in the input (basic COBS only;
///   COBS/R interprets that same situation as its reduced final block).
///
/// It extends [FormatException] so it can be caught with either
/// `on CobsDecodeException` or the more general `on FormatException`, matching
/// the convention used by `dart:convert` codecs such as `json` and `base64`.
///
/// The [offset] field, when set, is the index of the offending byte within the
/// encoded input, and [source] is the encoded input itself.
class CobsDecodeException extends FormatException {
  /// Creates a decode exception with a human-readable [message], and optionally
  /// the [source] bytes that failed to decode and the [offset] of the offending
  /// byte within them.
  const CobsDecodeException(super.message, [super.source, super.offset = -1]);
}
