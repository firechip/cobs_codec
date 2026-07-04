// Verifies this package against the shared conformance vectors from
// https://github.com/firechip/cobs-conformance
//
// Usage: dart run tool/conformance.dart <vectors.jsonl> [sentinel.jsonl] [errors.jsonl]
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cobs_codec/cobs_codec.dart';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String _toHex(List<int> b) =>
    b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main(List<String> args) {
  final path = args.isNotEmpty ? args[0] : 'vectors.jsonl';
  final sentinelPath = args.length > 1 ? args[1] : null;
  final errorsPath = args.length > 2 ? args[2] : null;
  var checked = 0;
  var failures = 0;

  void check(bool ok, String what) {
    if (!ok) {
      failures++;
      if (failures <= 10) stderr.writeln('MISMATCH: $what');
    }
  }

  for (final line in File(path).readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final v = json.decode(line) as Map<String, dynamic>;
    final decodedHex = v['decoded'] as String;
    final cobsHex = v['cobs'] as String;
    final cobsrHex = v['cobsr'] as String;
    final decoded = _hex(decodedHex);

    check(_toHex(cobsEncode(decoded)) == cobsHex, 'cobs encode $decodedHex');
    check(_toHex(cobsrEncode(decoded)) == cobsrHex, 'cobsr encode $decodedHex');
    check(_toHex(cobsDecode(_hex(cobsHex))) == decodedHex,
        'cobs decode $cobsHex');
    check(_toHex(cobsrDecode(_hex(cobsrHex))) == decodedHex,
        'cobsr decode $cobsrHex');
    checked++;
  }

  // Configurable-sentinel vectors: encode/decode round-trips for an arbitrary
  // sentinel byte, plus the invariant that the sentinel never appears in output.
  if (sentinelPath != null) {
    for (final line in File(sentinelPath).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final v = json.decode(line) as Map<String, dynamic>;
      final decodedHex = v['decoded'] as String;
      final sentinelHex = v['sentinel'] as String;
      final cobsHex = v['cobs'] as String;
      final cobsrHex = v['cobsr'] as String;
      final decoded = _hex(decodedHex);
      final sentinel = _hex(sentinelHex)[0];

      check(_toHex(cobsEncodeWithSentinel(decoded, sentinel)) == cobsHex,
          'sentinel $sentinelHex cobs encode $decodedHex');
      check(_toHex(cobsrEncodeWithSentinel(decoded, sentinel)) == cobsrHex,
          'sentinel $sentinelHex cobsr encode $decodedHex');
      check(
          _toHex(cobsDecodeWithSentinel(_hex(cobsHex), sentinel)) == decodedHex,
          'sentinel $sentinelHex cobs decode $cobsHex');
      check(
          _toHex(cobsrDecodeWithSentinel(_hex(cobsrHex), sentinel)) ==
              decodedHex,
          'sentinel $sentinelHex cobsr decode $cobsrHex');
      check(!_hex(cobsHex).contains(sentinel),
          'sentinel $sentinelHex present in cobs $cobsHex');
      check(!_hex(cobsrHex).contains(sentinel),
          'sentinel $sentinelHex present in cobsr $cobsrHex');
      checked++;
    }
  }

  // Error/decode-outcome vectors: decoding `encoded` must yield the expected
  // hex, or throw a CobsDecodeException when the expected value is JSON null.
  if (errorsPath != null) {
    void checkOutcome(String label, Uint8List input, Object? expected,
        Uint8List Function(List<int>) decode, String encodedHex) {
      if (expected == null) {
        var threw = false;
        try {
          decode(input);
        } on CobsDecodeException {
          threw = true;
        }
        check(threw, '$label decode should fail $encodedHex');
      } else {
        try {
          check(_toHex(decode(input)) == expected,
              '$label decode $encodedHex -> $expected');
        } on CobsDecodeException {
          check(false, '$label decode unexpectedly failed $encodedHex');
        }
      }
    }

    for (final line in File(errorsPath).readAsLinesSync()) {
      if (line.trim().isEmpty) continue;
      final v = json.decode(line) as Map<String, dynamic>;
      final encodedHex = v['encoded'] as String;
      final encoded = _hex(encodedHex);

      checkOutcome('cobs', encoded, v['cobs'], cobsDecode, encodedHex);
      checkOutcome('cobsr', encoded, v['cobsr'], cobsrDecode, encodedHex);
      checked++;
    }
  }

  stdout.writeln('Conformance: checked $checked vectors, $failures failures.');
  if (checked == 0) {
    stderr.writeln('ERROR: no vectors found in $path');
    exit(1);
  }
  if (failures > 0) exit(1);
}
