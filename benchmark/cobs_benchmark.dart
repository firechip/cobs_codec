// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Throughput micro-benchmarks for the COBS / COBS/R codecs.
///
/// Dev tooling only: this file is excluded from the published package via
/// `.pubignore` and is not part of the public API.
///
/// Run with:
///
/// ```sh
/// dart run benchmark/cobs_benchmark.dart
/// ```
///
/// Each benchmark processes a single 1 KiB (1024-byte) payload per `run()`.
/// `exercise()` is overridden to invoke `run()` exactly once, so
/// `BenchmarkBase.measure()` returns microseconds per operation. Throughput is
/// reported as `payloadBytes / time`; because one byte per microsecond equals
/// one decimal megabyte per second, `MB/s == payloadBytes / usPerOp`.
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:benchmark_harness/benchmark_harness.dart';
import 'package:cobs_codec/cobs_codec.dart';

/// Size of the representative payload, in bytes (1 KiB).
const int payloadBytes = 1024;

/// Builds a deterministic, mostly-non-zero payload with roughly one in eight
/// bytes set to `0x00`, so the COBS zero-delimited block path is exercised.
///
/// Uses a fixed-seed xorshift32 generator so the payload is identical across
/// runs and platforms, making results comparable over time.
Uint8List buildPayload(int length) {
  final data = Uint8List(length);
  var state = 0x12345678; // fixed seed -> reproducible pattern
  for (var i = 0; i < length; i++) {
    state ^= (state << 13) & 0xFFFFFFFF;
    state ^= state >> 17;
    state ^= (state << 5) & 0xFFFFFFFF;
    final b = state & 0xFF;
    // ~1/8 of bytes become zero; the rest keep a guaranteed-non-zero value.
    data[i] = (b & 7) == 0 ? 0 : b;
  }
  return data;
}

/// Benchmarks a full COBS encode of the 1 KiB payload.
class CobsEncodeBenchmark extends BenchmarkBase {
  CobsEncodeBenchmark(this.payload) : super('cobsEncode');

  final Uint8List payload;

  @override
  void exercise() => run();

  @override
  void run() {
    cobsEncode(payload);
  }
}

/// Benchmarks a full COBS decode of the encoded 1 KiB payload.
class CobsDecodeBenchmark extends BenchmarkBase {
  CobsDecodeBenchmark(this.encoded) : super('cobsDecode');

  final Uint8List encoded;

  @override
  void exercise() => run();

  @override
  void run() {
    cobsDecode(encoded);
  }
}

/// Benchmarks a full COBS/R encode of the 1 KiB payload.
class CobsrEncodeBenchmark extends BenchmarkBase {
  CobsrEncodeBenchmark(this.payload) : super('cobsrEncode');

  final Uint8List payload;

  @override
  void exercise() => run();

  @override
  void run() {
    cobsrEncode(payload);
  }
}

void main() {
  final payload = buildPayload(payloadBytes);
  final encoded = cobsEncode(payload);
  final zeros = payload.where((b) => b == 0).length;

  stdout.writeln('cobs_codec throughput benchmark');
  stdout.writeln('  Dart:    ${Platform.version}');
  stdout.writeln(
    '  OS:      ${Platform.operatingSystem} '
    '(${Platform.operatingSystemVersion})',
  );
  stdout.writeln(
    '  Payload: $payloadBytes bytes '
    '($zeros zero / ${payloadBytes - zeros} non-zero), '
    'COBS-encoded to ${encoded.length} bytes',
  );
  stdout.writeln();

  final benchmarks = <BenchmarkBase>[
    CobsEncodeBenchmark(payload),
    CobsDecodeBenchmark(encoded),
    CobsrEncodeBenchmark(payload),
  ];

  stdout.writeln('  benchmark      us/op       MB/s');
  stdout.writeln('  -----------  --------  ---------');
  for (final benchmark in benchmarks) {
    final usPerOp = benchmark.measure(); // microseconds per single run()
    // 1 byte/us == 1e6 bytes/s == 1 MB/s (decimal), so MB/s == bytes / us.
    final mbPerSecond = payloadBytes / usPerOp;
    stdout.writeln(
      '  ${benchmark.name.padRight(11)}  '
      '${usPerOp.toStringAsFixed(3).padLeft(8)}  '
      '${mbPerSecond.toStringAsFixed(1).padLeft(9)}',
    );
  }
}
