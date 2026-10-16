import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Collects the final [Digest] produced by a chunked hash conversion.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// Content hashing for the duplicate finder.
///
/// SHA-256 everywhere (never a weak digest): a false "these two files are
/// identical" would make the app delete real work, so collisions are not an
/// acceptable trade-off.
class Sha256FileHasher {
  const Sha256FileHasher._();

  /// Full-content digest, streamed in [chunkSize] slices so a 4 GB video
  /// never lands in memory.
  static Future<String> hashFile(String path, {int chunkSize = 1 << 20}) async {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    final handle = await File(path).open();
    try {
      while (true) {
        final chunk = await handle.read(chunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
    } finally {
      await handle.close();
    }
    input.close();
    return sink.value!.toString();
  }

  /// Synchronous full-content digest, for isolate workers where the
  /// synchronous read beats thousands of async round-trips.
  static String hashFileSync(String path, {int chunkSize = 1 << 20}) {
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    final handle = File(path).openSync();
    try {
      while (true) {
        final chunk = handle.readSync(chunkSize);
        if (chunk.isEmpty) break;
        input.add(chunk);
      }
    } finally {
      handle.closeSync();
    }
    input.close();
    return sink.value!.toString();
  }

  /// Synchronous head+tail pre-filter digest.
  static String partialHashSync(String path, int window) {
    final length = File(path).lengthSync();
    final w = window <= 0 ? 1 : window;
    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);
    final raf = File(path).openSync();
    try {
      final headLen = length < w ? length : w;
      input.add(raf.readSync(headLen));
      if (length > w) {
        input.add(_sizeBytes(length));
        raf.setPositionSync(length - w);
        input.add(raf.readSync(w));
      }
    } finally {
      raf.closeSync();
    }
    input.close();
    return sink.value!.toString();
  }

  /// Cheap pre-filter digest: first [window] bytes + last [window] bytes +
  /// the file size. Two files of equal size whose head *or* tail differ (the
  /// overwhelming majority) therefore never reach the full SHA-256 pass.
  static Future<String> partialHash(String path, int window) async {
    final file = File(path);
    final length = await file.length();
    final w = window <= 0 ? 1 : window;

    final sink = _DigestSink();
    final input = sha256.startChunkedConversion(sink);

    final raf = await file.open();
    try {
      final headLen = length < w ? length : w;
      input.add(await raf.read(headLen));
      if (length > w) {
        input.add(_sizeBytes(length));
        input.add(await raf.setPosition(length - w).then((r) => r.read(w)));
      }
    } finally {
      await raf.close();
    }
    input.close();
    return sink.value!.toString();
  }

  static Uint8List _sizeBytes(int length) {
    final b = ByteData(8)..setUint64(0, length);
    return b.buffer.asUint8List();
  }
}
