// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Packet framing helpers built on top of COBS.
///
/// Because COBS-encoded data never contains a zero byte, a single `0x00` byte
/// can safely delimit encoded packets on a byte stream such as a serial/UART
/// link. These helpers add and remove that delimiter and turn a raw byte stream
/// into a stream of decoded packets.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cobs.dart';
import 'exceptions.dart';

/// The byte value used to delimit COBS-encoded frames on the wire.
const int cobsDelimiter = 0x00;

/// Views [bytes] as a [Uint8List] without copying when possible.
Uint8List _asBytes(List<int> bytes) =>
    bytes is Uint8List ? bytes : Uint8List.fromList(bytes);

/// Encodes [packet] with [codec] (basic [cobs] by default) and appends the
/// [cobsDelimiter], producing a self-delimiting frame ready to transmit.
///
/// ```dart
/// final frame = cobsFrame([0x11, 0x00, 0x22]);
/// // [0x02, 0x11, 0x02, 0x22, 0x00]
/// ```
Uint8List cobsFrame(
  List<int> packet, {
  Codec<List<int>, List<int>> codec = cobs,
}) {
  final encoded = codec.encode(packet);
  final out = Uint8List(encoded.length + 1);
  out.setRange(0, encoded.length, encoded);
  // out[encoded.length] is already 0x00 (the delimiter).
  return out;
}

/// Splits [data] on the [cobsDelimiter] and decodes each frame with [codec],
/// returning the list of recovered packets.
///
/// Any trailing bytes after the final delimiter are treated as an incomplete
/// frame and ignored. When [skipEmpty] is true (the default), empty frames
/// (produced by consecutive or leading delimiters) are skipped rather than
/// decoded to empty packets.
///
/// Throws a [CobsDecodeException] if any complete frame is not valid encoded
/// data. Use [CobsFrameDecoder] to process a live [Stream] instead.
List<Uint8List> cobsUnframe(
  List<int> data, {
  Codec<List<int>, List<int>> codec = cobs,
  bool skipEmpty = true,
}) {
  final frames = <Uint8List>[];
  final bytes = _asBytes(data);
  var start = 0;
  for (var i = 0; i < bytes.length; i++) {
    if (bytes[i] == cobsDelimiter) {
      if (i == start) {
        if (!skipEmpty) frames.add(Uint8List(0));
      } else {
        frames.add(
            _asBytes(codec.decode(Uint8List.sublistView(bytes, start, i))));
      }
      start = i + 1;
    }
  }
  return frames;
}

/// A [StreamTransformer] that frames a stream of packets for transmission:
/// each incoming packet is COBS-encoded and followed by a [cobsDelimiter].
///
/// ```dart
/// outgoingPackets.transform(const CobsFrameEncoder()).pipe(serialSink);
/// ```
class CobsFrameEncoder extends StreamTransformerBase<List<int>, Uint8List> {
  /// Creates a frame encoder using [codec] (basic [cobs] by default).
  const CobsFrameEncoder({this.codec = cobs});

  /// The codec used to encode each packet.
  final Codec<List<int>, List<int>> codec;

  @override
  Stream<Uint8List> bind(Stream<List<int>> stream) async* {
    await for (final packet in stream) {
      yield cobsFrame(packet, codec: codec);
    }
  }
}

/// A [StreamTransformer] that turns a raw byte stream of [cobsDelimiter]-framed
/// data into a stream of decoded packets.
///
/// This is the counterpart to [CobsFrameEncoder] and the natural way to read
/// COBS packets from a serial/UART link, where bytes arrive in arbitrarily
/// sized chunks that do not align with frame boundaries. Bytes are buffered
/// across chunks until a delimiter completes a frame.
///
/// ```dart
/// serialPort // Stream<Uint8List> of raw bytes
///     .transform(const CobsFrameDecoder())
///     .listen(handlePacket);
/// ```
///
/// By default a frame that fails to decode adds a [CobsDecodeException] to the
/// output stream (which, if unhandled, cancels it). Provide [onInvalidFrame] to
/// instead handle the error and continue receiving — the recommended behaviour
/// for a noisy link, where one corrupt frame should not stop the receiver.
/// Empty frames are skipped when [skipEmpty] is true (the default). Any trailing
/// bytes with no final delimiter are discarded when the source stream closes.
///
/// Downstream pause, resume and cancel are propagated to the source stream even
/// during a long run of bytes that contains no delimiter, and [maxFrameLength]
/// bounds how many bytes are buffered for a single unterminated frame.
class CobsFrameDecoder extends StreamTransformerBase<List<int>, Uint8List> {
  /// Creates a frame decoder.
  const CobsFrameDecoder({
    this.codec = cobs,
    this.skipEmpty = true,
    this.maxFrameLength,
    this.onInvalidFrame,
  });

  /// The codec used to decode each frame.
  final Codec<List<int>, List<int>> codec;

  /// Whether to skip empty frames (from consecutive or leading delimiters)
  /// rather than emit empty packets.
  final bool skipEmpty;

  /// The maximum number of bytes buffered for a single in-progress frame before
  /// a delimiter completes it.
  ///
  /// When an unterminated frame exceeds this, the buffered bytes are discarded
  /// and a [CobsDecodeException] is reported (via [onInvalidFrame] if set,
  /// otherwise added to the output stream); decoding then resynchronises on the
  /// next delimiter. When `null` (the default) there is no limit — set it to
  /// bound memory use on an untrusted or noisy link that may never send the
  /// `0x00` delimiter.
  final int? maxFrameLength;

  /// Called for each frame that fails to decode, with the exception and the
  /// raw (still-encoded) frame bytes. When non-null, decoding continues with
  /// the next frame; when null, the exception is added to the output stream.
  final void Function(CobsDecodeException error, Uint8List frame)?
      onInvalidFrame;

  @override
  Stream<Uint8List> bind(Stream<List<int>> stream) {
    // A StreamController (rather than an `async*` generator) is used so that
    // downstream pause/resume/cancel propagate to the source subscription even
    // during a run of bytes with no delimiter. An `async*` body only observes
    // those signals at a `yield`, and this decoder only yields when a delimiter
    // completes a frame — so a delimiter-less run would otherwise ignore
    // backpressure and make the subscription impossible to cancel.
    final buffer = BytesBuilder(copy: false);
    late final StreamController<Uint8List> controller;
    StreamSubscription<List<int>>? subscription;

    void report(CobsDecodeException error, Uint8List frame,
        [StackTrace? stackTrace]) {
      final handler = onInvalidFrame;
      if (handler != null) {
        handler(error, frame);
      } else {
        controller.addError(error, stackTrace);
      }
    }

    void onData(List<int> chunk) {
      final bytes = _asBytes(chunk);
      var start = 0;
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] != cobsDelimiter) continue;
        // The delimiter completes a frame: buffered bytes + this chunk up to
        // (but not including) the delimiter. This sublist view is consumed
        // synchronously by takeBytes/decode below, so it need not be copied.
        buffer.add(Uint8List.sublistView(bytes, start, i));
        start = i + 1;
        final frame = buffer.takeBytes();
        if (frame.isEmpty) {
          if (!skipEmpty) controller.add(Uint8List(0));
          continue;
        }
        try {
          controller.add(_asBytes(codec.decode(frame)));
        } on CobsDecodeException catch (error, stackTrace) {
          report(error, frame, stackTrace);
        }
      }
      if (start < bytes.length) {
        // The partial frame is retained until a later chunk, so copy it: a
        // source that reuses its read buffer for the next chunk must not be
        // able to corrupt buffered frame data.
        buffer.add(Uint8List.fromList(Uint8List.sublistView(bytes, start)));
        final limit = maxFrameLength;
        if (limit != null && buffer.length > limit) {
          final partial = buffer.takeBytes();
          report(
            CobsDecodeException(
              'unterminated frame exceeds maxFrameLength ($limit bytes)',
              partial,
            ),
            partial,
          );
        }
      }
    }

    controller = StreamController<Uint8List>(
      onListen: () {
        subscription = stream.listen(
          onData,
          onError: controller.addError,
          onDone: controller.close,
        );
      },
      onPause: () => subscription?.pause(),
      onResume: () => subscription?.resume(),
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }
}
