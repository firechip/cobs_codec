// Verifies this package against the shared conformance vectors from
// https://github.com/firechip/cobs-conformance
//
// Usage: dart run tool/conformance.dart <vectors.jsonl>
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
    check(_toHex(cobsDecode(_hex(cobsHex))) == decodedHex, 'cobs decode $cobsHex');
    check(_toHex(cobsrDecode(_hex(cobsrHex))) == decodedHex,
        'cobsr decode $cobsrHex');
    checked++;
  }

  stdout.writeln('Conformance: checked $checked vectors, $failures failures.');
  if (checked == 0) {
    stderr.writeln('ERROR: no vectors found in $path');
    exit(1);
  }
  if (failures > 0) exit(1);
}
