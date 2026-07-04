// Copyright (c) 2026 Alexander Salas Bastidas <ajsb85@firechip.dev>
// SPDX-License-Identifier: MIT

/// Consistent Overhead Byte Stuffing (COBS) and COBS/R for Dart.
///
/// COBS encodes an arbitrary sequence of bytes into a form that contains no
/// zero (`0x00`) bytes, at a small and *predictable* cost: at most one extra
/// byte per 254 bytes of input, plus one. That makes a single `0x00` a reliable
/// packet delimiter for serial, UART, USB-CDC, TCP and other byte streams,
/// which is why COBS is popular in embedded and robotics protocols.
///
/// See "Consistent Overhead Byte Stuffing" by Stuart Cheshire and Mary Baker,
/// IEEE/ACM Transactions on Networking, Vol. 7, No. 2, April 1999.
///
/// ## Encoding and decoding
///
/// The [cobs] and [cobsr] top-level instances mirror `dart:convert` codecs such
/// as `json` and `base64`:
///
/// ```dart
/// import 'package:cobs_codec/cobs_codec.dart';
///
/// final encoded = cobs.encode([0x11, 0x22, 0x00, 0x33]);
/// final decoded = cobs.decode(encoded); // [0x11, 0x22, 0x00, 0x33]
/// ```
///
/// [cobsr] (COBS/R, "Reduced") often saves the trailing overhead byte, which is
/// valuable for small messages.
///
/// ## Framing a byte stream
///
/// Use [cobsFrame] / [CobsFrameEncoder] to append the `0x00` delimiter, and
/// [CobsFrameDecoder] to recover packets from a live [Stream] of raw bytes:
///
/// ```dart
/// serialPort
///     .transform(const CobsFrameDecoder())
///     .listen(handlePacket);
/// ```
library;

export 'src/cobs.dart'
    show
        CobsCodec,
        CobsDecoder,
        CobsEncoder,
        cobs,
        cobsDecode,
        cobsDecodeInPlace,
        cobsDecodeInPlaceWithSentinel,
        cobsDecodeWithSentinel,
        cobsEncode,
        cobsEncodeWithSentinel;
export 'src/cobsr.dart'
    show
        CobsrCodec,
        CobsrDecoder,
        CobsrEncoder,
        cobsr,
        cobsrDecode,
        cobsrDecodeInPlace,
        cobsrDecodeInPlaceWithSentinel,
        cobsrDecodeWithSentinel,
        cobsrEncode,
        cobsrEncodeWithSentinel;
export 'src/exceptions.dart' show CobsDecodeException;
export 'src/framing.dart'
    show
        CobsFrameDecoder,
        CobsFrameEncoder,
        cobsDelimiter,
        cobsFrame,
        cobsUnframe;
export 'src/overhead.dart'
    show cobsMaxBlockLength, encodingOverhead, maxEncodedLength;
