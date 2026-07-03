// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

// Demonstrates the main features of package:cobs_codec.
//
// Run with: dart run example/cobs_codec_example.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:cobs_codec/cobs_codec.dart';

void main() async {
  // 1. Basic COBS encode / decode. The encoding never contains a 0x00 byte.
  final message = Uint8List.fromList([0x11, 0x22, 0x00, 0x33]);
  final encoded = cobs.encode(message);
  print('message : ${hex(message)}');
  print('COBS    : ${hex(encoded)}'); // 03 11 22 02 33  (no zeros)
  print('decoded : ${hex(cobs.decode(encoded))}');
  print('');

  // 2. COBS/R often saves the trailing overhead byte for small messages.
  final small = Uint8List.fromList([0x31, 0x32, 0x33, 0x34, 0x35]); // "12345"
  print('COBS    of "12345": ${hex(cobs.encode(small))}'); // 06 31 32 33 34 35
  print('COBS/R  of "12345": ${hex(cobsr.encode(small))}'); // 35 31 32 33 34
  print('');

  // 3. Framing: append the 0x00 delimiter so packets are self-delimiting.
  final frame = cobsFrame(message);
  print('framed  : ${hex(frame)}'); // ... trailing 00 delimiter
  print('unframed: ${cobsUnframe(frame).map(hex).toList()}');
  print('');

  // 4. Streaming: decode packets from a raw byte stream whose chunks do not
  //    align with frame boundaries (as happens on a real serial link).
  final wire = <Uint8List>[
    cobsFrame([0x01, 0x02]),
    cobsFrame([0x00, 0xFF]),
    cobsFrame([0x2A]),
  ];
  // Re-chunk the wire bytes arbitrarily to simulate a serial link.
  final allBytes = wire.expand((f) => f).toList();
  final chunks = <List<int>>[
    allBytes.sublist(0, 3),
    allBytes.sublist(3, 7),
    allBytes.sublist(7),
  ];

  final packets = await Stream.fromIterable(chunks)
      .transform(const CobsFrameDecoder())
      .toList();
  print('stream packets: ${packets.map(hex).toList()}');

  // 5. Size bounds without encoding anything.
  print('');
  print('max encoded length of 1000 bytes: ${maxEncodedLength(1000)}');
}

String hex(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
