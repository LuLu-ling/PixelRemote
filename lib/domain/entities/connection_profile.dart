/// A saved destination: an SSH address plus where the VNC server listens on
/// the far side of the tunnel.
final class ConnectionProfile {
  const ConnectionProfile({
    required this.id,
    required this.address,
    this.name = '',
    this.vncHost = 'localhost',
    this.vncPort = 5900,
    this.identityFile,
    this.startCommand,
    this.lastConnected,
  });

  final String id;
  final String address;
  final String name;
  final String vncHost;
  final int vncPort;
  final String? identityFile;
  final String? startCommand;
  final DateTime? lastConnected;

  String get displayName => name.isEmpty ? address : name;

  static String newId() => DateTime.now().microsecondsSinceEpoch.toRadixString(36);

  ConnectionProfile touched(DateTime at) => ConnectionProfile(
        id: id,
        address: address,
        name: name,
        vncHost: vncHost,
        vncPort: vncPort,
        identityFile: identityFile,
        startCommand: startCommand,
        lastConnected: at,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'address': address,
        'name': name,
        'vncHost': vncHost,
        'vncPort': vncPort,
        'identityFile': identityFile,
        'startCommand': startCommand,
        'lastConnected': lastConnected?.toIso8601String(),
      };

  factory ConnectionProfile.fromJson(Map<String, Object?> j) => ConnectionProfile(
        id: j['id'] as String,
        address: j['address'] as String,
        name: j['name'] as String? ?? '',
        vncHost: j['vncHost'] as String? ?? 'localhost',
        vncPort: j['vncPort'] as int? ?? 5900,
        identityFile: j['identityFile'] as String?,
        startCommand: j['startCommand'] as String?,
        lastConnected: DateTime.tryParse(j['lastConnected'] as String? ?? ''),
      );
}
