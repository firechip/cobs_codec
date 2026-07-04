// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT
//
// ignore_for_file: avoid_print

/// Throughput micro-benchmarks for the COBS / COBS/R codecs.
///
/// Dev tooling only: this file is excluded from the published package via
/// `.pubignore`, is not part of the public API, and has no package
/// dependencies (a plain `Stopwatch`, so it runs on every supported SDK).
///
/// Run with:
///
/// ```sh
/// dart run benchmark/cobs_benchmark.dart
/// ```
///
/// Each operation processes a single 1 KiB (1024-byte) payload; throughput is
/// reported as decimal MB/s (`payloadBytes * iterations / seconds / 1e6`).
library;

import 'dart:typed_data';

import 'package:cobs_codec/cobs_codec.dart';

/// A deterministic 1 KiB payload with roughly one zero byte in eight, so the
/// COBS block-splitting path is exercised.
Uint8List _makePayload(int length) {
  final bytes = Uint8List(length);
  var state = 0x12345678;
  for (var i = 0; i < length; i++) {
    state = (state * 1103515245 + 12345) & 0x7fffffff;
    bytes[i] = (state % 8 == 0) ? 0 : (state & 0xff);
  }
  return bytes;
}

/// Warms up, then times [operation] over many iterations and prints its
/// throughput in decimal MB/s relative to [payloadBytes] bytes per call.
double _benchmark(String name, int payloadBytes, void Function() operation) {
  for (var i = 0; i < 20000; i++) {
    operation();
  }
  const iterations = 500000;
  final stopwatch = Stopwatch()..start();
  for (var i = 0; i < iterations; i++) {
    operation();
  }
  stopwatch.stop();
  final seconds = stopwatch.elapsedMicroseconds / 1e6;
  final mbps = payloadBytes * iterations / seconds / 1e6;
  print('${name.padRight(12)} ${mbps.toStringAsFixed(1)} MB/s');
  return mbps;
}

void main() {
  final payload = _makePayload(1024);
  final encoded = cobsEncode(payload);

  _benchmark('cobsEncode', payload.length, () => cobsEncode(payload));
  _benchmark('cobsDecode', payload.length, () => cobsDecode(encoded));
  _benchmark('cobsrEncode', payload.length, () => cobsrEncode(payload));
}
