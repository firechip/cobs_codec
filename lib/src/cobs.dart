// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Basic Consistent Overhead Byte Stuffing (COBS).
library;

import 'dart:convert';
import 'dart:typed_data';

import 'exceptions.dart';
import 'overhead.dart' as sizes;
import 'sink.dart';

/// A canonical, const [CobsCodec] instance.
///
/// Mirrors the top-level codec instances in `dart:convert` (`json`, `utf8`,
/// `base64`), so the common cases read naturally:
///
/// ```dart
/// final encoded = cobs.encode([0x11, 0x00, 0x22]); // [0x02, 0x11, 0x02, 0x22]
/// final decoded = cobs.decode(encoded);            // [0x11, 0x00, 0x22]
/// ```
const CobsCodec cobs = CobsCodec();

/// Encodes [input] with basic COBS, returning a zero-free [Uint8List].
///
/// The output never contains a `0x00` byte, so a `0x00` may be used to delimit
/// encoded packets on the wire (see the framing helpers). Encoding never fails:
/// any sequence of bytes is encodable. The empty input encodes to `[0x01]`.
///
/// Byte values in [input] are treated modulo 256 (only the low 8 bits are
/// used), matching how a `Uint8List` stores data.
///
/// This is a convenience wrapper around [cobs]`.encode`.
Uint8List cobsEncode(List<int> input) {
  final srcLen = input.length;
  if (srcLen == 0) {
    return Uint8List(1)..[0] = 0x01;
  }

  // Worst-case output size; the actual output is a prefix of this buffer.
  final dst = Uint8List(sizes.maxEncodedLength(srcLen));

  // `codeIndex` reserves the slot for the current block's length code; data
  // bytes are written at `writeIndex`. This is the classic single-pass encoder
  // from the COBS paper (Cheshire & Baker, 1999, Appendix, Listing 1).
  var codeIndex = 0;
  var writeIndex = 1;
  var code = 1;
  var readIndex = 0;

  while (true) {
    final byte = input[readIndex++] & 0xFF;
    if (byte == 0) {
      // Close the current block at this (implicit) zero.
      dst[codeIndex] = code;
      codeIndex = writeIndex++;
      code = 1;
      if (readIndex >= srcLen) break;
    } else {
      dst[writeIndex++] = byte;
      code++;
      // The final byte terminates the loop before the 0xFF split so that a
      // chunk of exactly 254 non-zero bytes does not emit a spurious trailing
      // block.
      if (readIndex >= srcLen) break;
      if (code == 0xFF) {
        dst[codeIndex] = code;
        codeIndex = writeIndex++;
        code = 1;
      }
    }
  }
  dst[codeIndex] = code;

  return Uint8List.sublistView(dst, 0, writeIndex);
}

/// Decodes basic-COBS-encoded [input], returning the original bytes.
///
/// Throws a [CobsDecodeException] if [input] is not valid COBS: that is, if it
/// contains a `0x00` byte, or a length code points past the end of the input.
///
/// The empty input decodes to an empty list. Input should be a single encoded
/// packet with no surrounding `0x00` delimiter bytes; use the framing helpers to
/// split a delimited stream into packets first.
///
/// This is a convenience wrapper around [cobs]`.decode`.
Uint8List cobsDecode(List<int> input) {
  final srcLen = input.length;
  if (srcLen == 0) return Uint8List(0);

  // Decoded output is always strictly shorter than the encoded input.
  final out = Uint8List(srcLen);
  var writeIndex = 0;
  var index = 0;

  while (true) {
    final code = input[index] & 0xFF;
    if (code == 0) {
      throw CobsDecodeException('zero byte in COBS input', input, index);
    }
    index++;
    final blockEnd = index + code - 1;
    final copyEnd = blockEnd < srcLen ? blockEnd : srcLen;
    for (; index < copyEnd; index++) {
      final byte = input[index] & 0xFF;
      if (byte == 0) {
        throw CobsDecodeException('zero byte in COBS input', input, index);
      }
      out[writeIndex++] = byte;
    }
    // `index` is now `blockEnd` (possibly past the input if the block was
    // truncated).
    if (blockEnd > srcLen) {
      throw CobsDecodeException(
        'length code points past end of input',
        input,
        blockEnd - code, // index of the offending length code
      );
    }
    if (blockEnd < srcLen) {
      // A non-maximal block carries an implicit trailing zero.
      if (code < 0xFF) out[writeIndex++] = 0;
    } else {
      break;
    }
  }

  return Uint8List.sublistView(out, 0, writeIndex);
}

/// A [Codec] that encodes and decodes bytes with basic Consistent Overhead Byte
/// Stuffing (COBS).
///
/// Encoding produces a [Uint8List] that is free of `0x00` bytes and at most
/// `n + n/254 + 1` bytes long for an `n`-byte input. Use the top-level [cobs]
/// instance rather than constructing this directly.
///
/// As a [Codec] it composes with `dart:convert`: `cobs.encoder`, `cobs.decoder`,
/// `cobs.fuse(...)`, and streaming via `Stream.transform`. When used as a
/// chunked converter, all chunks are treated as pieces of a single packet and
/// the result is emitted when the input is closed. To encode or decode a stream
/// of many `0x00`-delimited packets, use the framing transformers instead.
class CobsCodec extends Codec<List<int>, List<int>> {
  /// Creates a COBS codec. Prefer the shared [cobs] instance.
  const CobsCodec();

  @override
  Uint8List encode(List<int> input) => cobsEncode(input);

  @override
  Uint8List decode(List<int> encoded) => cobsDecode(encoded);

  @override
  Converter<List<int>, List<int>> get encoder => const CobsEncoder();

  @override
  Converter<List<int>, List<int>> get decoder => const CobsDecoder();

  /// The maximum length of the COBS encoding of a [sourceLength]-byte message.
  /// See the top-level `maxEncodedLength`.
  int maxEncodedLength(int sourceLength) =>
      sizes.maxEncodedLength(sourceLength);

  /// The maximum overhead COBS adds to a [sourceLength]-byte message.
  /// See the top-level `encodingOverhead`.
  int encodingOverhead(int sourceLength) =>
      sizes.encodingOverhead(sourceLength);
}

/// The [Converter] that implements COBS encoding for [CobsCodec].
class CobsEncoder extends Converter<List<int>, List<int>> {
  /// Creates a COBS encoder.
  const CobsEncoder();

  @override
  Uint8List convert(List<int> input) => cobsEncode(input);

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) =>
      accumulatingByteSink(sink, cobsEncode);
}

/// The [Converter] that implements COBS decoding for [CobsCodec].
class CobsDecoder extends Converter<List<int>, List<int>> {
  /// Creates a COBS decoder.
  const CobsDecoder();

  @override
  Uint8List convert(List<int> input) => cobsDecode(input);

  @override
  Sink<List<int>> startChunkedConversion(Sink<List<int>> sink) =>
      accumulatingByteSink(sink, cobsDecode);
}
