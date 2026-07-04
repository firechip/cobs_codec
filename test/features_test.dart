// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cobs_codec/cobs_codec.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // The six sentinels exercised by the reference feature tests: 0x00 selects the
  // plain path and the rest are spread across the byte range.
  const sentinels = [0x00, 0x01, 0x2A, 0x7F, 0xAA, 0xFF];

  List<int> randomPacket(Random rng, int max) =>
      List<int>.generate(rng.nextInt(max + 1), (_) => rng.nextInt(256));

  group('sentinel encoding', () {
    test('avoids the sentinel and round-trips (COBS and COBS/R)', () {
      final rng = Random(0x5E170001);
      for (final s in sentinels) {
        for (var t = 0; t < 2000; t++) {
          final packet = randomPacket(rng, 600);

          final enc = cobsEncodeWithSentinel(packet, s);
          expect(enc, isNot(contains(s)),
              reason: 'COBS output must avoid sentinel $s');
          expect(cobsDecodeWithSentinel(enc, s), packet);

          final encr = cobsrEncodeWithSentinel(packet, s);
          expect(encr, isNot(contains(s)),
              reason: 'COBS/R output must avoid sentinel $s');
          expect(cobsrDecodeWithSentinel(encr, s), packet);
        }
      }
    });

    test('sentinel 0 is identical to the plain codecs', () {
      final rng = Random(0x5E173333);
      for (var t = 0; t < 2000; t++) {
        final packet = randomPacket(rng, 600);
        expect(cobsEncodeWithSentinel(packet, 0), cobsEncode(packet));
        expect(cobsrEncodeWithSentinel(packet, 0), cobsrEncode(packet));
      }
    });

    test('a known message round-trips under every sentinel', () {
      final packet = ascii('hello\x00world');
      for (final s in sentinels) {
        final enc = cobsEncodeWithSentinel(packet, s);
        expect(enc, isNot(contains(s)));
        expect(cobsDecodeWithSentinel(enc, s), packet);
      }
    });

    test('decode never mutates the caller input', () {
      final packet = [0x11, 0x00, 0x22, 0xFF];
      final enc = cobsEncodeWithSentinel(packet, 0xAA);
      final snapshot = Uint8List.fromList(enc);
      expect(cobsDecodeWithSentinel(enc, 0xAA), packet);
      expect(enc, snapshot, reason: 'input must be left untouched');
    });
  });

  group('in-place decode', () {
    test('matches slice decode for every sentinel (differential)', () {
      final rng = Random(0x1234A17A);
      for (final s in sentinels) {
        for (var t = 0; t < 4000; t++) {
          final packet = randomPacket(rng, 700);
          final encoded = cobsEncodeWithSentinel(packet, s);
          final expected = cobsDecodeWithSentinel(encoded, s);

          final buf = Uint8List.fromList(encoded);
          final n = cobsDecodeInPlaceWithSentinel(buf, s);
          expect(Uint8List.sublistView(buf, 0, n), expected);
          expect(Uint8List.sublistView(buf, 0, n), packet);
        }
      }
    });

    test('cobsDecodeInPlace matches cobsDecode (differential)', () {
      final rng = Random(0x0FF1CE01);
      for (var t = 0; t < 4000; t++) {
        final packet = randomPacket(rng, 700);
        final encoded = cobsEncode(packet);
        final buf = Uint8List.fromList(encoded);
        final n = cobsDecodeInPlace(buf);
        expect(Uint8List.sublistView(buf, 0, n), cobsDecode(encoded));
      }
    });

    test('cobsrDecodeInPlace matches cobsrDecode (differential)', () {
      // Assert that the in-place COBS/R decoder agrees byte-for-byte with the
      // slice decoder on valid input, and agrees on acceptance vs rejection for
      // arbitrary (possibly invalid) input.
      void checkAgrees(List<int> encoded) {
        Uint8List? sliceResult;
        var sliceThrew = false;
        try {
          sliceResult = cobsrDecode(encoded);
        } on CobsDecodeException {
          sliceThrew = true;
        }

        final buf = Uint8List.fromList(encoded);
        Uint8List? inPlaceResult;
        var inPlaceThrew = false;
        try {
          final n = cobsrDecodeInPlace(buf);
          inPlaceResult = Uint8List.sublistView(buf, 0, n);
        } on CobsDecodeException {
          inPlaceThrew = true;
        }

        expect(inPlaceThrew, sliceThrew,
            reason: 'accept/reject must match for $encoded');
        if (!sliceThrew) {
          expect(inPlaceResult, sliceResult, reason: 'decoding $encoded');
        }
      }

      // Golden COBS/R encoded vectors (ported from cobsr_test.dart), chosen to
      // exercise reduced final blocks, embedded zeros, and maximal (0xFF) codes.
      final golden = <List<int>>[
        [0x01],
        [0x02],
        [0x7F],
        [0xFF],
        [0x02, 0x01],
        [0x03, ...ascii('a'), 0x02],
        [0x03, ...ascii('a')],
        [0xFF, ...ascii('a')],
        [0x06, 0x05, 0x04, 0x03, 0x02, 0x01],
        [0x35, ...ascii('1234')],
        [0x06, ...ascii('12345'), 0x05, 0x04, 0x03, 0x02, 0x01],
        [0x06, ...ascii('12345'), ...ascii('9678')],
        [0x01, 0x06, ...ascii('12345'), ...ascii('9678')],
        [0x06, ...ascii('12345'), 0x05, ...ascii('6789'), 0x01],
        [0x01, 0x01],
        [0x01, 0x01, 0x01],
        [0xFE, ...range(1, 254)],
        [0xFF, ...range(1, 255)],
        [0xFF, ...range(1, 255), 0xFF],
        [0x01, 0xFF, ...range(1, 255), 0xFF],
      ];
      for (final encoded in golden) {
        checkAgrees(encoded);
      }

      // Large seeded-random corpus.
      final rng = Random(0xC0B5B12A);
      for (var t = 0; t < 6000; t++) {
        // Valid encodings from the reference encoder exercise the reduced-block
        // path and embedded-zero blocks.
        checkAgrees(cobsrEncode(randomPacket(rng, 700)));

        // Raw random bytes are mostly invalid (embedded zeros / bad codes) and
        // pin down accept/reject agreement between the two decoders.
        final rawLen = rng.nextInt(48);
        checkAgrees(List<int>.generate(rawLen, (_) => rng.nextInt(256)));

        // Non-zero random bytes are always valid COBS/R and heavily exercise
        // high length codes and reduced final blocks.
        final nzLen = 1 + rng.nextInt(48);
        checkAgrees(List<int>.generate(nzLen, (_) => 1 + rng.nextInt(255)));
      }
    });

    test('cobsrDecodeInPlaceWithSentinel matches slice decode (differential)',
        () {
      final rng = Random(0x1234C0B5);
      for (final s in sentinels) {
        for (var t = 0; t < 4000; t++) {
          final packet = randomPacket(rng, 700);
          final encoded = cobsrEncodeWithSentinel(packet, s);
          final expected = cobsrDecodeWithSentinel(encoded, s);

          final buf = Uint8List.fromList(encoded);
          final n = cobsrDecodeInPlaceWithSentinel(buf, s);
          expect(Uint8List.sublistView(buf, 0, n), expected);
          expect(Uint8List.sublistView(buf, 0, n), packet);
        }
      }
    });
  });

  group('framing with a sentinel', () {
    test('round-trips through cobsFrame / cobsUnframe (COBS and COBS/R)', () {
      final rng = Random(0x57EA9000);
      for (final s in sentinels) {
        for (final codec in <Codec<List<int>, List<int>>>[cobs, cobsr]) {
          for (var t = 0; t < 300; t++) {
            final count = 1 + rng.nextInt(6);
            final packets = <List<int>>[
              for (var i = 0; i < count; i++) randomPacket(rng, 300),
            ];
            final wire = <int>[
              for (final p in packets)
                ...cobsFrame(p, codec: codec, sentinel: s),
            ];
            final got = cobsUnframe(wire, codec: codec, sentinel: s);
            expect(got, packets);
          }
        }
      }
    });

    test('CobsFrameDecoder reassembles sentinel frames byte-by-byte', () async {
      const s = 0xAA;
      final packets = <List<int>>[
        [0x11, 0x00, 0x22],
        [0x00],
        [0xFF, 0xFF],
      ];
      final wire = <int>[
        for (final p in packets) ...cobsFrame(p, sentinel: s),
      ];
      final got = await Stream.fromIterable(wire.map((b) => [b]))
          .transform(const CobsFrameDecoder(sentinel: s))
          .toList();
      expect(got, packets);
    });
  });
}
