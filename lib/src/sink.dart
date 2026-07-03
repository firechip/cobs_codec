// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Internal support for chunked (`startChunkedConversion`) COBS conversion.
library;

import 'dart:typed_data';

/// Returns a [Sink] that accumulates all added byte chunks, then applies
/// [convert] to the concatenated bytes once and forwards the single result to
/// [out] when closed.
///
/// COBS and COBS/R operate on a whole packet, so — following the `dart:convert`
/// contract that chunked input is one logical message — the encoding or
/// decoding is deferred until [Sink.close]. To process a stream of many
/// delimited packets, use the framing transformers instead.
Sink<List<int>> accumulatingByteSink(
  Sink<List<int>> out,
  Uint8List Function(List<int>) convert,
) =>
    _AccumulatingByteSink(out, convert);

class _AccumulatingByteSink implements Sink<List<int>> {
  _AccumulatingByteSink(this._out, this._convert);

  final Sink<List<int>> _out;
  final Uint8List Function(List<int>) _convert;
  // BytesBuilder copies added chunks by default; added chunks are retained until
  // close(), so a caller that reuses its buffer between chunks cannot corrupt
  // them.
  final BytesBuilder _buffer = BytesBuilder();
  bool _closed = false;

  @override
  void add(List<int> chunk) {
    if (_closed) {
      throw StateError('Cannot add to a closed sink');
    }
    _buffer.add(chunk);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    _out
      ..add(_convert(_buffer.takeBytes()))
      ..close();
  }
}
