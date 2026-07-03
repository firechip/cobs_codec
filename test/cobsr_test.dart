// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:cobs_codec/cobs_codec.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // Golden vectors ported from the reference COBS/R test suite. Each pair is
  // (decoded, encoded).
  final predefined = <List<List<int>>>[
    [
      ascii(''),
      [0x01]
    ],
    [
      [0x01],
      [0x02, 0x01],
    ],
    [
      [0x02],
      [0x02],
    ],
    [
      [0x03],
      [0x03],
    ],
    [
      [0x7E],
      [0x7E],
    ],
    [
      [0x7F],
      [0x7F],
    ],
    [
      [0x80],
      [0x80],
    ],
    [
      [0xD5],
      [0xD5],
    ],
    [
      [0xFE],
      [0xFE],
    ],
    [
      [0xFF],
      [0xFF],
    ],
    [
      [...ascii('a'), 0x02],
      [0x03, ...ascii('a'), 0x02],
    ],
    [
      [...ascii('a'), 0x03],
      [0x03, ...ascii('a')],
    ],
    [
      [...ascii('a'), 0xFF],
      [0xFF, ...ascii('a')],
    ],
    [
      [0x05, 0x04, 0x03, 0x02, 0x01],
      [0x06, 0x05, 0x04, 0x03, 0x02, 0x01],
    ],
    [
      ascii('12345'),
      [0x35, ...ascii('1234')]
    ],
    [
      [...ascii('12345'), 0, 0x04, 0x03, 0x02, 0x01],
      [0x06, ...ascii('12345'), 0x05, 0x04, 0x03, 0x02, 0x01],
    ],
    [
      [...ascii('12345'), 0, ...ascii('6789')],
      [0x06, ...ascii('12345'), ...ascii('9678')],
    ],
    [
      [0, ...ascii('12345'), 0, ...ascii('6789')],
      [0x01, 0x06, ...ascii('12345'), ...ascii('9678')],
    ],
    [
      [...ascii('12345'), 0, ...ascii('6789'), 0],
      [0x06, ...ascii('12345'), 0x05, ...ascii('6789'), 0x01],
    ],
    [
      [0],
      [0x01, 0x01],
    ],
    [
      [0, 0],
      [0x01, 0x01, 0x01],
    ],
    [
      [0, 0, 0],
      [0x01, 0x01, 0x01, 0x01],
    ],
    [
      range(1, 254),
      [0xFE, ...range(1, 254)]
    ],
    [
      range(1, 255),
      [0xFF, ...range(1, 255)]
    ],
    [
      range(1, 256),
      [0xFF, ...range(1, 255), 0xFF],
    ],
    [
      range(0, 256),
      [0x01, 0xFF, ...range(1, 255), 0xFF],
    ],
    [
      range(2, 256),
      [0xFF, ...range(2, 255)]
    ],
  ];

  group('cobsr.encode', () {
    test('matches predefined golden vectors', () {
      for (final [decoded, encoded] in predefined) {
        expect(cobsr.encode(decoded), encoded, reason: 'encoding $decoded');
      }
    });

    test('function and codec agree', () {
      for (final [decoded, encoded] in predefined) {
        expect(cobsrEncode(decoded), cobsr.encode(decoded));
        expect(cobsr.encode(decoded), encoded);
      }
    });

    test('never larger than basic COBS, and never contains a zero', () {
      final rng = Random(0x600B5B);
      for (var t = 0; t < 3000; t++) {
        final len = rng.nextInt(2000);
        final data = List.generate(len, (_) => rng.nextInt(256));
        final encoded = cobsr.encode(data);
        expect(encoded, isNot(contains(0)));
        expect(encoded.length, lessThanOrEqualTo(cobs.encode(data).length));
      }
    });
  });

  group('cobsr.decode', () {
    test('matches predefined golden vectors', () {
      for (final [decoded, encoded] in predefined) {
        expect(cobsr.decode(encoded), decoded, reason: 'decoding $encoded');
      }
    });

    test('rejects invalid input', () {
      final bad = <List<int>>[
        [0x00],
        [0x05, ...ascii('1234'), 0x00],
        [0x05, ...ascii('12'), 0x00, 0x34],
      ];
      for (final input in bad) {
        expect(() => cobsr.decode(input), throwsA(isA<CobsDecodeException>()),
            reason: 'should reject $input');
      }
    });
  });

  group('round trip', () {
    test('all-zero messages of length 0..519', () {
      for (var len = 0; len < 520; len++) {
        final data = List.filled(len, 0);
        final encoded = cobsr.encode(data);
        expect(encoded, List.filled(len + 1, 0x01), reason: '$len zeros');
        expect(cobsr.decode(encoded), data, reason: 'decoding $len zeros');
      }
    });

    test('non-zero messages of length 1..999', () {
      for (var len = 1; len < 1000; len++) {
        final data = nonZeroBytes(len);
        expect(cobsr.decode(cobsr.encode(data)), data, reason: 'length $len');
      }
    });

    test('random data of length 0..2000', () {
      final rng = Random(0x600B5);
      for (var t = 0; t < 5000; t++) {
        final len = rng.nextInt(2001);
        final data = List.generate(len, (_) => rng.nextInt(256));
        final encoded = cobsr.encode(data);
        expect(encoded.length, lessThanOrEqualTo(maxEncodedLength(len)));
        expect(cobsr.decode(encoded), data);
      }
    });
  });
}
