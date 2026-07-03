// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

import 'dart:math';

import 'package:cobs_codec/cobs_codec.dart';
import 'package:test/test.dart';

import 'support.dart';

void main() {
  // Golden vectors ported from the reference COBS test suite. Each pair is
  // (decoded, encoded).
  final predefined = <List<List<int>>>[
    [
      ascii(''),
      [0x01]
    ],
    [
      ascii('1'),
      [0x02, 0x31]
    ],
    [
      ascii('12345'),
      [0x06, ...ascii('12345')]
    ],
    [
      [...ascii('12345'), 0, ...ascii('6789')],
      [0x06, ...ascii('12345'), 0x05, ...ascii('6789')],
    ],
    [
      [0, ...ascii('12345'), 0, ...ascii('6789')],
      [0x01, 0x06, ...ascii('12345'), 0x05, ...ascii('6789')],
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
      [0xFF, ...range(1, 255), 0x02, 0xFF],
    ],
    [
      range(0, 256),
      [0x01, 0xFF, ...range(1, 255), 0x02, 0xFF],
    ],
  ];

  group('cobs.encode', () {
    test('matches predefined golden vectors', () {
      for (final [decoded, encoded] in predefined) {
        expect(cobs.encode(decoded), encoded, reason: 'encoding $decoded');
      }
    });

    test('function and codec agree', () {
      for (final [decoded, encoded] in predefined) {
        expect(cobsEncode(decoded), cobs.encode(decoded));
        expect(cobs.encode(decoded), encoded);
      }
    });

    test('output never contains a zero byte', () {
      final rng = Random(20260703);
      for (var t = 0; t < 2000; t++) {
        final len = rng.nextInt(2000);
        final data = List.generate(len, (_) => rng.nextInt(256));
        expect(cobs.encode(data), isNot(contains(0)));
      }
    });
  });

  group('cobs.decode', () {
    test('matches predefined golden vectors', () {
      for (final [decoded, encoded] in predefined) {
        expect(cobs.decode(encoded), decoded, reason: 'decoding $encoded');
      }
    });

    test('rejects invalid input', () {
      final bad = <List<int>>[
        [0x00],
        [0x05, ...ascii('123')],
        [0x05, ...ascii('1234'), 0x00],
        [0x05, ...ascii('12'), 0x00, 0x34],
      ];
      for (final input in bad) {
        expect(() => cobs.decode(input), throwsA(isA<CobsDecodeException>()),
            reason: 'should reject $input');
      }
    });

    test('CobsDecodeException is a FormatException', () {
      expect(() => cobs.decode([0x00]), throwsFormatException);
    });
  });

  group('round trip', () {
    test('all-zero messages of length 0..519', () {
      for (var len = 0; len < 520; len++) {
        final data = List.filled(len, 0);
        final encoded = cobs.encode(data);
        expect(encoded, List.filled(len + 1, 0x01),
            reason: 'encoding $len zeros');
        expect(cobs.decode(encoded), data, reason: 'decoding $len zeros');
      }
    });

    test('non-zero messages of length 1..999', () {
      for (var len = 1; len < 1000; len++) {
        final data = nonZeroBytes(len);
        expect(cobs.encode(data), simpleEncodeNonZeros(data),
            reason: 'length $len');
        expect(cobs.decode(cobs.encode(data)), data, reason: 'length $len');
      }
    });

    test('non-zero messages with a trailing zero', () {
      for (var len = 1; len < 1000; len++) {
        final nonZeros = nonZeroBytes(len);
        final data = [...nonZeros, 0];
        final expected = [
          ...simpleEncodeNonZeros(nonZeros),
          if (nonZeros.length % 254 == 0) ...[0x01, 0x01] else 0x01,
        ];
        expect(cobs.encode(data), expected, reason: 'length $len');
        expect(cobs.decode(cobs.encode(data)), data, reason: 'length $len');
      }
    });

    test('random data of length 0..2000', () {
      final rng = Random(0xC0B5);
      for (var t = 0; t < 5000; t++) {
        final len = rng.nextInt(2001);
        final data = List.generate(len, (_) => rng.nextInt(256));
        final encoded = cobs.encode(data);
        expect(encoded.length, lessThanOrEqualTo(maxEncodedLength(len)));
        expect(cobs.decode(encoded), data);
      }
    });
  });

  group('size helpers', () {
    test('encodingOverhead', () {
      expect(encodingOverhead(0), 1);
      expect(encodingOverhead(5), 1);
      expect(encodingOverhead(254), 1);
      expect(encodingOverhead(255), 2);
    });

    test('maxEncodedLength', () {
      expect(maxEncodedLength(0), 1);
      expect(maxEncodedLength(5), 6);
      expect(maxEncodedLength(254), 255);
      expect(maxEncodedLength(255), 257);
    });

    test('negative length throws', () {
      expect(() => encodingOverhead(-1), throwsArgumentError);
      expect(() => maxEncodedLength(-1), throwsArgumentError);
    });

    test('codec exposes the same size helpers', () {
      expect(cobs.maxEncodedLength(255), 257);
      expect(cobs.encodingOverhead(255), 2);
    });
  });
}
