// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

import 'dart:async';
import 'dart:typed_data';

import 'package:cobs_codec/cobs_codec.dart';
import 'package:test/test.dart';

void main() {
  group('cobsFrame / cobsUnframe', () {
    test('appends the delimiter and round-trips', () {
      final packet = [0x11, 0x00, 0x22];
      final frame = cobsFrame(packet);
      expect(frame.last, cobsDelimiter);
      expect(frame, [0x02, 0x11, 0x02, 0x22, 0x00]);
      expect(cobsUnframe(frame).single, packet);
    });

    test('splits multiple frames', () {
      final wire = [
        ...cobsFrame([0x01, 0x02]),
        ...cobsFrame([0x00]),
        ...cobsFrame([0xFF, 0xFF]),
      ];
      final packets = cobsUnframe(wire);
      expect(packets, [
        [0x01, 0x02],
        [0x00],
        [0xFF, 0xFF],
      ]);
    });

    test('skips empty frames by default but can keep them', () {
      final wire = [
        0x00,
        ...cobsFrame([0x42]),
        0x00,
        0x00
      ];
      expect(cobsUnframe(wire), [
        [0x42],
      ]);
      expect(cobsUnframe(wire, skipEmpty: false), [
        <int>[],
        [0x42],
        <int>[],
        <int>[],
      ]);
    });

    test('ignores trailing bytes with no final delimiter', () {
      final wire = [
        ...cobsFrame([0x01]),
        0x02,
        0x03
      ]; // dangling partial frame
      expect(cobsUnframe(wire), [
        [0x01],
      ]);
    });

    test('supports COBS/R framing', () {
      final frame = cobsFrame([0x31, 0x32, 0x33, 0x34, 0x35], codec: cobsr);
      expect(frame, [0x35, 0x31, 0x32, 0x33, 0x34, 0x00]);
      expect(cobsUnframe(frame, codec: cobsr).single,
          [0x31, 0x32, 0x33, 0x34, 0x35]);
    });
  });

  group('CobsFrameEncoder', () {
    test('encodes and delimits each packet', () async {
      final packets = [
        [0x01, 0x02],
        [0x00],
      ];
      final out = await Stream.fromIterable(packets)
          .transform(const CobsFrameEncoder())
          .toList();
      expect(out, [
        [0x03, 0x01, 0x02, 0x00],
        [0x01, 0x01, 0x00],
      ]);
    });
  });

  group('CobsFrameDecoder', () {
    test('reassembles packets across arbitrary chunk boundaries', () async {
      final wire = [
        ...cobsFrame([0x01, 0x02]),
        ...cobsFrame([0x00, 0xFF]),
        ...cobsFrame([0x2A]),
      ];
      // Re-chunk into misaligned pieces.
      final chunks = <List<int>>[
        wire.sublist(0, 1),
        wire.sublist(1, 6),
        wire.sublist(6, 7),
        wire.sublist(7),
      ];
      final packets = await Stream.fromIterable(chunks)
          .transform(const CobsFrameDecoder())
          .toList();
      expect(packets, [
        [0x01, 0x02],
        [0x00, 0xFF],
        [0x2A],
      ]);
    });

    test('byte-at-a-time delivery still yields whole packets', () async {
      final wire = [
        ...cobsFrame([0xAA, 0x00, 0xBB]),
        ...cobsFrame([0x01]),
      ];
      final packets = await Stream.fromIterable(wire.map((b) => [b]))
          .transform(const CobsFrameDecoder())
          .toList();
      expect(packets, [
        [0xAA, 0x00, 0xBB],
        [0x01],
      ]);
    });

    test('propagates decode errors by default', () {
      // First frame is valid; the second's length code (0x05) points past its
      // end, which is invalid for basic COBS.
      final wire = [
        ...cobsFrame([0x11]),
        0x05,
        0x01,
        0x00,
      ];
      expect(
        Stream.fromIterable([wire])
            .transform(const CobsFrameDecoder())
            .toList(),
        throwsA(isA<CobsDecodeException>()),
      );
    });

    test('onInvalidFrame keeps the stream alive', () async {
      final errors = <Object>[];
      final wire = [
        ...cobsFrame([0x11]),
        0x05, 0x01, 0x00, // invalid frame
        ...cobsFrame([0x22]),
      ];
      final packets = await Stream.fromIterable([wire])
          .transform(CobsFrameDecoder(
            onInvalidFrame: (error, frame) => errors.add(error),
          ))
          .toList();
      expect(packets, [
        [0x11],
        [0x22],
      ]);
      expect(errors, hasLength(1));
      expect(errors.single, isA<CobsDecodeException>());
    });
  });

  group('CobsFrameDecoder robustness', () {
    test('cancel tears down the source during an unterminated frame', () async {
      var sourceCancelled = false;
      final src = StreamController<List<int>>()
        ..onCancel = () {
          sourceCancelled = true;
        };
      final received = <List<int>>[];
      final sub =
          src.stream.transform(const CobsFrameDecoder()).listen(received.add);

      src
        ..add(cobsFrame([0x11])) // one complete frame
        ..add(List.filled(100000, 0x01)); // long delimiter-less run
      await Future<void>.delayed(Duration.zero);

      // Must complete promptly even though we are mid-(unterminated)-frame.
      await sub.cancel().timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('cancel did not complete: subscription leak'),
          );

      expect(sourceCancelled, isTrue, reason: 'upstream should be torn down');
      expect(received, [
        [0x11],
      ]);
      await src.close();
    });

    test('honours downstream pause between delimiters', () async {
      final src = StreamController<List<int>>();
      final sub = src.stream.transform(const CobsFrameDecoder()).listen((_) {});
      // Pause the output; the source subscription should be paused too.
      sub.pause();
      await Future<void>.delayed(Duration.zero);
      expect(src.isPaused, isTrue,
          reason: 'source must be paused while output is paused');
      sub.resume();
      await Future<void>.delayed(Duration.zero);
      expect(src.isPaused, isFalse);
      await sub.cancel();
      await src.close();
    });

    test('maxFrameLength discards an oversized unterminated frame', () async {
      final errors = <CobsDecodeException>[];
      final received = <List<int>>[];
      final chunks = <List<int>>[
        List.filled(50, 0x01), // 50 buffered, under the limit
        List.filled(60, 0x01), // 110 buffered, over the 100 limit -> discard
        cobsFrame([0x22]), // a clean frame after resync
      ];
      await Stream.fromIterable(chunks)
          .transform(CobsFrameDecoder(
            maxFrameLength: 100,
            onInvalidFrame: (error, frame) => errors.add(error),
          ))
          .forEach(received.add);
      expect(errors, hasLength(1));
      expect(received, [
        [0x22],
      ]);
    });

    test('tolerates a source that reuses its read buffer', () async {
      final backing = Uint8List(4);
      Stream<List<int>> reuseStream() async* {
        // Chunk 1: partial frame [0x04, 0x11] with no delimiter.
        backing.setRange(0, 2, [0x04, 0x11]);
        yield Uint8List.sublistView(backing, 0, 2);
        // Chunk 2: overwrite the same backing store, completing the frame.
        backing.setRange(0, 3, [0x22, 0x33, 0x00]);
        yield Uint8List.sublistView(backing, 0, 3);
      }

      final packets =
          await reuseStream().transform(const CobsFrameDecoder()).toList();
      // Frame body [0x04, 0x11, 0x22, 0x33] decodes to [0x11, 0x22, 0x33].
      expect(packets, [
        [0x11, 0x22, 0x33],
      ]);
    });
  });
}
