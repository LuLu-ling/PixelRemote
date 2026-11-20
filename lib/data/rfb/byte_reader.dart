import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import '../../domain/errors.dart';

/// Turns a chunked byte stream into exact-size async reads.
final class ByteReader {
  ByteReader(Stream<Uint8List> source) {
    _subscription = source.listen(
      _onData,
      onError: (Object e) => _fail(RemoteException(RemoteErrorKind.disconnected, '$e')),
      onDone: () => _fail(const RemoteException(RemoteErrorKind.disconnected)),
    );
  }

  late final StreamSubscription<Uint8List> _subscription;
  final _chunks = ListQueue<Uint8List>();
  int _head = 0, _available = 0, _wanted = 0, _consumed = 0;
  Completer<void>? _waiter;
  RemoteException? _error;

  /// Total bytes handed out so far (used for per-frame bandwidth accounting).
  int get consumed => _consumed;

  Future<Uint8List> read(int n) async {
    while (_available < n) {
      if (_error case final error?) throw error;
      _wanted = n;
      await (_waiter = Completer<void>()).future;
    }
    return _take(n);
  }

  Future<int> u8() async => (await read(1))[0];
  Future<int> u16() async => ByteData.sublistView(await read(2)).getUint16(0);
  Future<int> u32() async => ByteData.sublistView(await read(4)).getUint32(0);

  Future<void> cancel() {
    _fail(const RemoteException(RemoteErrorKind.disconnected));
    return _subscription.cancel();
  }

  void _onData(Uint8List chunk) {
    if (chunk.isEmpty) return;
    _chunks.add(chunk);
    _available += chunk.length;
    if (_available >= _wanted) _wake();
  }

  void _fail(RemoteException e) {
    _error ??= e;
    _wake();
  }

  void _wake() {
    final waiter = _waiter;
    _waiter = null;
    waiter?.complete();
  }

  Uint8List _take(int n) {
    _available -= n;
    _consumed += n;
    final first = _chunks.isEmpty ? null : _chunks.first;
    if (first != null && first.length - _head >= n) {
      final out = Uint8List.sublistView(first, _head, _head + n);
      _advance(first, n);
      return out;
    }
    final out = Uint8List(n);
    for (var o = 0; o < n;) {
      final chunk = _chunks.first;
      final k = (n - o).clamp(0, chunk.length - _head);
      out.setRange(o, o + k, chunk, _head);
      o += k;
      _advance(chunk, k);
    }
    return out;
  }

  void _advance(Uint8List chunk, int k) {
    _head += k;
    if (_head == chunk.length) {
      _chunks.removeFirst();
      _head = 0;
    }
  }
}
