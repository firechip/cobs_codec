// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Shared helpers for the cobs_codec test suite.
library;

/// ASCII code units of [s] (used to write byte vectors readably).
List<int> ascii(String s) => s.codeUnits;

/// `[start, end)` as a list of ints, like Python's `range`.
List<int> range(int start, int end) => [for (var i = start; i < end; i++) i];

/// Deterministic stream of non-zero bytes, matching the reference test suites'
/// `infinite_non_zero_generator`, truncated to [length] bytes.
List<int> nonZeroBytes(int length) {
  final out = <int>[];
  outer:
  while (true) {
    for (var i = 1; i < 50; i++) {
      for (var j = 1; j < 256; j += i) {
        if (out.length == length) break outer;
        out.add(j);
      }
    }
  }
  return out;
}

/// The naive block encoding of a run containing no zero bytes: split into
/// 254-byte blocks, each prefixed with `length + 1`.
List<int> simpleEncodeNonZeros(List<int> input) {
  final out = <int>[];
  for (var i = 0; i < input.length; i += 254) {
    final end = (i + 254) < input.length ? i + 254 : input.length;
    final block = input.sublist(i, end);
    out
      ..add(block.length + 1)
      ..addAll(block);
  }
  return out;
}
