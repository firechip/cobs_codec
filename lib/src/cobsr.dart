// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Consistent Overhead Byte Stuffing — Reduced (COBS/R).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'exceptions.dart';
import 'overhead.dart' as sizes;
import 'sink.dart';

/// A canonical, const [CobsrCodec] instance.
///
/// COBS/R (a variant devised by Craig McQueen) often avoids the `+1` byte that
/// basic COBS always adds, which is worthwhile when encoding many small
/// messages:
///
/// ```dart
/// cobsr.encode([0x31, 0x32, 0x33, 0x34, 0x35]); // [0x35, 0x31, 0x32, 0x33, 0x34]
/// cobs.encode([0x31, 0x32, 0x33, 0x34, 0x35]);  // [0x06, 0x31, 0x32, 0x33, 0x34, 0x35]
/// ```
const CobsrCodec cobsr = CobsrCodec();

/// Encodes [input] with COBS/R, returning a zero-free [Uint8List].
///
/// COBS/R is identical to basic COBS except that, when the final data byte's
/// value is greater than or equal to the final length code, that data byte is
/// used as the length code and dropped from the tail — saving one byte. The
/// output never contains a `0x00` byte and is never larger than the basic COBS
/// encoding. The empty input encodes to `[0x01]`.
///
/// Byte values in [input] are treated modulo 256.
Uint8List cobsrEncode(List<int> input) {
  final srcLen = input.length;

  // COBS/R can save one byte, but never exceeds COBS's worst-case size.
  final dst = Uint8List(sizes.maxEncodedLength(srcLen));

  // The block-building loop is identical to basic COBS; only the finalisation
  // differs. `codeIndex` reserves the current block's length code and data is
  // written at `writeIndex`.
  var codeIndex = 0;
  var writeIndex = 1;
  var code = 1;
  var lastByte = 0;

  if (srcLen != 0) {
    var readIndex = 0;
    while (true) {
      final byte = input[readIndex++] & 0xFF;
      lastByte = byte;
      if (byte == 0) {
        dst[codeIndex] = code;
        codeIndex = writeIndex++;
        code = 1;
        if (readIndex >= srcLen) break;
      } else {
        dst[writeIndex++] = byte;
        code++;
        if (readIndex >= srcLen) break;
        if (code == 0xFF) {
          dst[codeIndex] = code;
          codeIndex = writeIndex++;
          code = 1;
        }
      }
    }
  }

  // COBS/R reduction: if the final data byte's value is >= the length code that
  // basic COBS would write, use that byte as the length code and drop it from
  // the tail, saving one byte. The decoder recovers it because the length code
  // then points past the end of the input.
  if (lastByte < code) {
    dst[codeIndex] = code; // identical to basic COBS
  } else {
    dst[codeIndex] = lastByte;
    writeIndex--; // remove the (duplicated) final data byte
  }

  return Uint8List.sublistView(dst, 0, writeIndex);
}

/// Decodes COBS/R-encoded [input], returning the original bytes.
///
/// Throws a [CobsDecodeException] if [input] contains a `0x00` byte. Unlike
/// basic COBS, a length code that points past the end of the input is not an
/// error in COBS/R: it signals the reduced final block, and the length code
/// itself is appended as the final data byte.
///
/// The empty input decodes to an empty list.
Uint8List cobsrDecode(List<int> input) {
  final srcLen = input.length;
  if (srcLen == 0) return Uint8List(0);

  // The reduced final block can make the output as long as the input.
  final out = Uint8List(srcLen);
  var writeIndex = 0;
  var index = 0;

  while (true) {
    final code = input[index] & 0xFF;
    if (code == 0) {
      throw CobsDecodeException('zero byte in COBS/R input', input, index);
    }
    index++;
    final blockEnd = index + code - 1;
    final copyEnd = blockEnd < srcLen ? blockEnd : srcLen;
    for (; index < copyEnd; index++) {
      final byte = input[index] & 0xFF;
      if (byte == 0) {
        throw CobsDecodeException('zero byte in COBS/R input', input, index);
      }
      out[writeIndex++] = byte;
    }
    if (blockEnd > srcLen) {
      // Reduced encoding: the length code was really the final data byte.
      out[writeIndex++] = code;
      break;
    } else if (blockEnd < srcLen) {
      if (code < 0xFF) out[writeIndex++] = 0;
    } else {
      break;
    }
  }

  return Uint8List.sublistView(out, 0, writeIndex);
}

/// A [Codec] that encodes and decodes bytes with Consistent Overhead Byte
/// Stuffing — Reduced (COBS/R).
///
/// Behaves like [CobsCodec] but can save one byte per message. Use the
/// top-level [cobsr] instance rather than constructing this directly. See
/// [CobsCodec] for notes on chunked (`Stream.transform`) behaviour.
class CobsrCodec extends Codec<List<int>, List<int>> {
  /// Creates a COBS/R codec. Prefer the shared [cobsr] instance.
  const CobsrCodec();

  @override
  Uint8List encode(List<int> input) => cobsrEncode(input);

  @override
  Uint8List decode(List<int> encoded) => cobsrDecode(encoded);

  @override
  Converter<List<int>, List<int>> get encoder => const CobsrEncoder();

  @override
  Converter<List<int>, List<int>> get decoder => const CobsrDecoder();

  /// The maximum length of the COBS/R encoding of a [sourceLength]-byte message
  /// (equal to the basic-COBS bound). See the top-level `maxEncodedLength`.
  int maxEncodedLength(int sourceLength) =>
      sizes.maxEncodedLength(sourceLength);

  /// The maximum overhead COBS/R adds to a [sourceLength]-byte message.
  /// See the top-level `encodingOverhead`.
  int encodingOverhead(int sourceLength) =>
      sizes.encodingOverhead(sourceLength);
}

/// The [Converter] that implements COBS/R encoding for [CobsrCodec].
class CobsrEncoder extends Converter<List<int>, List<int>> {
  /// Creates a COBS/R encoder.
  const CobsrEncoder();

  @override
  Uint8List convert(List<int> input) => cobsrEncode(input);

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) =>
      accumulatingByteSink(sink, cobsrEncode);
}

/// The [Converter] that implements COBS/R decoding for [CobsrCodec].
class CobsrDecoder extends Converter<List<int>, List<int>> {
  /// Creates a COBS/R decoder.
  const CobsrDecoder();

  @override
  Uint8List convert(List<int> input) => cobsrDecode(input);

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) =>
      accumulatingByteSink(sink, cobsrDecode);
}
