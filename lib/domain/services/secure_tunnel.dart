import 'dart:typed_data';

import '../entities/ssh_address.dart';
import 'session_log.dart';

/// A bidirectional byte pipe, e.g. one SSH direct-tcpip channel.
abstract interface class ByteChannel {
  Stream<Uint8List> get input;
  void write(List<int> bytes);
  Future<void> close();
}

/// An authenticated, encrypted connection to a remote host.
abstract interface class SecureTunnel {
  /// Opens a channel to [host]:[port] as seen from the remote host.
  Future<ByteChannel> open(String host, int port);

  /// Runs [command] remotely and returns its combined output.
  Future<String> run(String command);

  /// Starts a long-running remote process (e.g. a VNC server) without waiting.
  Future<void> spawn(String command);

  /// Measures one round trip through the encrypted connection.
  Future<Duration> ping();

  Future<void> get done;
  Future<void> close();
}

abstract interface class TunnelConnector {
  Future<SecureTunnel> connect(SshEndpoint endpoint, SessionLog log);
}

/// Expands what the user typed (aliases, defaults) into a concrete endpoint.
abstract interface class SshEndpointResolver {
  SshEndpoint resolve(SshAddress address, {String? identityFile});
}
