# cobs_codec

[![CI](https://github.com/firechip/cobs_codec/actions/workflows/ci.yml/badge.svg)](https://github.com/firechip/cobs_codec/actions/workflows/ci.yml)
[![pub package](https://img.shields.io/pub/v/cobs_codec.svg)](https://pub.dev/packages/cobs_codec)
[![pub points](https://img.shields.io/pub/points/cobs_codec)](https://pub.dev/packages/cobs_codec/score)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Fast, dependency-free **Consistent Overhead Byte Stuffing (COBS)** and **COBS/R**
codecs for Dart and Flutter, with first-class `dart:convert` integration and
stream framing for serial links.

COBS encodes an arbitrary byte sequence into one that contains **no zero
(`0x00`) bytes**, at a small and *predictable* cost — at most **one extra byte
per 254 bytes**, plus one. That lets a single `0x00` reliably delimit packets on
a byte stream (serial/UART, USB-CDC, TCP, BLE, …), so a receiver can always
resynchronise on the next `0x00` even after a corrupt packet. Unlike escape-based
schemes such as PPP byte stuffing, COBS never doubles a packet's size.

## Features

- ⚡ **Basic COBS** and **COBS/R (Reduced)** — pick the standard scheme, or COBS/R
  to shave the trailing overhead byte off small messages.
- 🧩 **`dart:convert` native** — `cobs` and `cobsr` are `Codec`s, so they
  `fuse`, `transform` streams, and compose like `json`/`utf8`/`base64`.
- 🔌 **Stream framing built in** — turn a raw serial byte stream into a stream of
  decoded packets with `CobsFrameDecoder`; chunk boundaries don't have to align
  with frames.
- 🚩 **Configurable delimiter (sentinel)** — encode and decode COBS *and* COBS/R
  so the output avoids any chosen byte, not just `0x00`, letting that byte delimit
  frames instead.
- 🏷️ **Sentinel-aware framing** — the framing helpers and the stream decoder can
  split on the chosen `sentinel` rather than `0x00`.
- ♻️ **In-place decode** — decode basic COBS inside the same buffer with no second
  allocation; COBS never expands on decode.
- 🎯 **Zero dependencies, all platforms** — pure Dart (`dart:typed_data`), works
  on mobile, desktop, web, server and CLI. Uses `Uint8List` throughout.
- 📏 **Predictable sizing** — `maxEncodedLength` / `encodingOverhead` for buffer
  pre-allocation.
- ✅ **Reference-verified** — tested against the golden vectors from the original
  COBS and COBS/R implementations.

## Install

```console
dart pub add cobs_codec
```

```yaml
dependencies:
  cobs_codec: ^1.1.0
```

## Usage

### Encode and decode

```dart
import 'package:cobs_codec/cobs_codec.dart';

void main() {
  final data = [0x11, 0x22, 0x00, 0x33];

  final encoded = cobs.encode(data); // [0x03, 0x11, 0x22, 0x02, 0x33] — no 0x00
  final decoded = cobs.decode(encoded); // [0x11, 0x22, 0x00, 0x33]
}
```

`cobs.encode` returns a `Uint8List` and never fails — any input is encodable.
`cobs.decode` throws a `CobsDecodeException` (a `FormatException`) if the input
is not valid COBS.

### COBS/R — save a byte

COBS always adds exactly one byte to messages of 254 bytes or fewer. COBS/R
opportunistically avoids that byte when the final data byte allows it:

```dart
cobs.encode([0x31, 0x32, 0x33, 0x34, 0x35]);  // [0x06, 0x31, 0x32, 0x33, 0x34, 0x35]
cobsr.encode([0x31, 0x32, 0x33, 0x34, 0x35]); // [0x35, 0x31, 0x32, 0x33, 0x34]  (same size!)
```

Both round-trip losslessly; just decode with the matching codec.

### Framing a packet stream

COBS output has no `0x00`, so append one to delimit frames:

```dart
final frame = cobsFrame([0x11, 0x00, 0x22]); // [0x02, 0x11, 0x02, 0x22, 0x00]

final packets = cobsUnframe(buffer); // List<Uint8List>, one per 0x00-delimited frame
```

### Reading packets from a serial stream

`CobsFrameDecoder` is a `StreamTransformer` that buffers bytes across arbitrarily
chunked reads and emits one decoded packet per completed frame — exactly what you
want on a UART:

```dart
import 'package:cobs_codec/cobs_codec.dart';

// `serialPort` is any Stream<List<int>> of incoming bytes.
serialPort
    .transform(CobsFrameDecoder(
      // Keep receiving even if a frame is corrupted on a noisy link.
      onInvalidFrame: (error, rawFrame) => print('dropped bad frame: $error'),
      // Bound memory if a peer never sends the 0x00 delimiter.
      maxFrameLength: 4096,
    ))
    .listen((packet) => handlePacket(packet));

// Sending: encode + delimit each outgoing packet.
outgoingPackets
    .transform(const CobsFrameEncoder())
    .listen(serialPort.add);
```

### A custom delimiter byte (sentinel)

Need a delimiter other than `0x00` — say a byte your protocol reserves for
framing? The `…WithSentinel` variants make the encoding avoid an arbitrary
`sentinel` byte instead (they XOR the finished encoding with it), so that byte can
delimit frames:

```dart
final data = [0x11, 0x22, 0x00, 0x33];

final encoded = cobsEncodeWithSentinel(data, 0xAA); // [0xA9, 0xBB, 0x88, 0xA8, 0x99] — no 0xAA
final decoded = cobsDecodeWithSentinel(encoded, 0xAA); // [0x11, 0x22, 0x00, 0x33]

// COBS/R has the same pair.
cobsrEncodeWithSentinel(data, 0xAA); // [0xA9, 0xBB, 0x88, 0x99]
```

`sentinel == 0` is byte-for-byte identical to the plain codec, and decoding never
mutates its input.

### Decoding in place

Basic COBS never expands on decode, so it can be decoded within the same buffer —
no second allocation. `cobsDecodeInPlace` overwrites the buffer with the decoded
bytes and returns their length:

```dart
final buffer = Uint8List.fromList(cobs.encode([0x11, 0x22, 0x00, 0x33]));
// buffer == [0x03, 0x11, 0x22, 0x02, 0x33]

final n = cobsDecodeInPlace(buffer);                 // 4
final decoded = Uint8List.sublistView(buffer, 0, n); // [0x11, 0x22, 0x00, 0x33]
```

`cobsDecodeInPlaceWithSentinel(buffer, sentinel)` does the same for a custom
delimiter. (COBS/R can expand on decode, so it has no in-place form.)

### Framing on a custom sentinel

`cobsFrame` / `cobsUnframe` and both stream transformers take the same optional
`sentinel`, so a whole link can be delimited by a byte other than `0x00`:

```dart
final frame = cobsFrame([0x11, 0x00, 0x22], sentinel: 0xAA); // [0xA8, 0xBB, 0xA8, 0x88, 0xAA]
final packets = cobsUnframe(frame, sentinel: 0xAA);          // [[0x11, 0x00, 0x22]]

// The stream decoder frames on the same byte:
serialPort.transform(const CobsFrameDecoder(sentinel: 0xAA));
```

### Composing with other codecs

Because they are `Codec`s, you can `fuse` COBS with anything:

```dart
// Encode a Dart object to JSON, to UTF-8 bytes, then COBS-frame it.
final pipeline = json.fuse(utf8).fuse(cobs);
final wire = pipeline.encode({'id': 7, 'ok': true});
final obj = pipeline.decode(wire);
```

### Sizing buffers

```dart
encodingOverhead(0);      // 1
encodingOverhead(254);    // 1
encodingOverhead(255);    // 2
maxEncodedLength(1000);   // 1004
```

## How much overhead?

| Input length *n*      | Max encoded length | Overhead      |
| --------------------- | ------------------ | ------------- |
| 0 (empty)             | 1                  | +1 byte       |
| 1 – 254               | *n* + 1            | +1 byte       |
| 255 – 508             | *n* + 2            | +2 bytes      |
| *n*                   | *n* + ⌈*n* / 254⌉  | ≤ ~0.4%       |

The overhead is *data-independent*: worst case and average case are almost the
same. Compare PPP/SLIP escape stuffing, whose worst case **doubles** the packet.

## API overview

| Symbol | Description |
| ------ | ----------- |
| `cobs` / `cobsr` | Shared `Codec` instances (basic COBS and COBS/R). |
| `cobsEncode` / `cobsDecode` | Direct basic-COBS functions. |
| `cobsrEncode` / `cobsrDecode` | Direct COBS/R functions. |
| `cobsEncodeWithSentinel` / `cobsDecodeWithSentinel` | Basic COBS against an arbitrary delimiter byte. |
| `cobsrEncodeWithSentinel` / `cobsrDecodeWithSentinel` | COBS/R against an arbitrary delimiter byte. |
| `cobsDecodeInPlace` / `cobsDecodeInPlaceWithSentinel` | Decode basic COBS within the buffer; returns the length. |
| `CobsCodec`, `CobsEncoder`, `CobsDecoder` | `dart:convert` classes for basic COBS. |
| `CobsrCodec`, `CobsrEncoder`, `CobsrDecoder` | `dart:convert` classes for COBS/R. |
| `cobsFrame` / `cobsUnframe` | Add / split the frame delimiter (`0x00` or a custom `sentinel`). |
| `CobsFrameEncoder` / `CobsFrameDecoder` | Stream transformers for framed links (optional `sentinel`). |
| `cobsDelimiter` | The frame delimiter byte (`0x00`). |
| `encodingOverhead` / `maxEncodedLength` | Size bounds. |
| `cobsMaxBlockLength` | Max data bytes per COBS block (`254`). |
| `CobsDecodeException` | Thrown on invalid encoded input. |

> **Note on decoding.** `decode` expects a *single* encoded packet with **no**
> surrounding `0x00` delimiter — split a delimited stream into frames first (with
> `cobsUnframe` or `CobsFrameDecoder`). This matches the reference COBS
> implementations, where framing is the application's responsibility.

## Background

COBS is described in:

> Stuart Cheshire and Mary Baker, "Consistent Overhead Byte Stuffing,"
> *IEEE/ACM Transactions on Networking*, Vol. 7, No. 2, April 1999.

**COBS/R** ("Reduced") was devised by **Craig McQueen**, whose C and Python
reference implementations were used to validate this package's test vectors. The
COBS/ZPE and COBS/ZRE variants are not implemented.

## Contributing

Contributions are welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT © 2026 Alexander Salas Bastidas ([Firechip](https://firechip.dev)). See
[LICENSE](LICENSE).
