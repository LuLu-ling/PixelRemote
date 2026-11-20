enum RemoteErrorKind {
  invalidAddress,
  hostUnreachable,
  authFailed,
  hostKeyRejected,
  hostKeyChanged,
  vncUnavailable,
  vncAuthFailed,
  unsupportedSecurity,
  protocol,
  disconnected,
  cancelled,
}

/// The one exception type that crosses layer boundaries. Infrastructure maps
/// library-specific failures onto a [kind]; the UI maps kinds onto messages.
final class RemoteException implements Exception {
  const RemoteException(this.kind, [this.detail]);

  final RemoteErrorKind kind;
  final String? detail;

  @override
  String toString() => 'RemoteException(${kind.name}${detail == null ? '' : ': $detail'})';
}
