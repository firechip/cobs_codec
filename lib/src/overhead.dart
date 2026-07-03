// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Size calculations for COBS-encoded data.
library;

/// The largest number of source bytes that a single COBS code block can carry
/// without emitting an overhead byte.
const int cobsMaxBlockLength = 254;

/// Returns the maximum encoding overhead, in bytes, that COBS or COBS/R can add
/// when encoding a message of [sourceLength] bytes.
///
/// COBS adds at most one byte for every 254 bytes of input (rounded up), and at
/// least one byte for any message — including the empty message. The overhead
/// is therefore a tight, data-independent bound:
///
/// ```dart
/// encodingOverhead(0);   // 1
/// encodingOverhead(5);   // 1
/// encodingOverhead(254); // 1
/// encodingOverhead(255); // 2
/// ```
///
/// Throws [ArgumentError] if [sourceLength] is negative.
int encodingOverhead(int sourceLength) {
  if (sourceLength < 0) {
    throw ArgumentError.value(
      sourceLength,
      'sourceLength',
      'must not be negative',
    );
  }
  if (sourceLength == 0) return 1;
  return (sourceLength + (cobsMaxBlockLength - 1)) ~/ cobsMaxBlockLength;
}

/// Returns the maximum possible length, in bytes, of the COBS (or COBS/R)
/// encoding of a message of [sourceLength] bytes.
///
/// This is [sourceLength] plus [encodingOverhead]. It is useful for
/// pre-allocating an output buffer. COBS always produces output of exactly this
/// size for worst-case (zero-free) input; COBS/R may produce one byte less.
///
/// Throws [ArgumentError] if [sourceLength] is negative.
int maxEncodedLength(int sourceLength) =>
    sourceLength + encodingOverhead(sourceLength);
