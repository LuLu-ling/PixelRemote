import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../../domain/errors.dart';
import '../../domain/services/session_log.dart';
import 'byte_reader.dart';
import 'rfb_wire.dart';

final class ServerInit {
  const ServerInit(this.width, this.height, this.name);

  final int width, height;
  final String name;
}

/// RFB 3.3/3.7/3.8 handshake: version, security (None or VNC auth), init.
/// Inside an SSH tunnel the transport is already encrypted and authenticated.
Future<ServerInit> performHandshake(
  ByteReader input,
  void Function(List<int>) write,
  Future<String?> Function() password,
  SessionLog log,
) async {
  const src = 'rfb';
  final bannerText = ascii.decode(await input.read(12), allowInvalid: true);
  final banner = RegExp(r'^RFB (\d{3})\.(\d{3})\n$').firstMatch(bannerText);
  if (banner == null) throw const RemoteException(RemoteErrorKind.protocol, 'not a VNC server');
  final major = int.parse(banner[1]!), minor = int.parse(banner[2]!);
  final version = major > 3 || minor >= 8 ? 8 : (minor >= 7 ? 7 : 3);
  log.info(src, 'Server speaks ${bannerText.trim()}${minor == 889 ? ' (Apple)' : ''}; using RFB 3.$version');
  write(ascii.encode('RFB 003.00$version\n'));

  const none = 1, vncAuth = 2;
  final int type;
  if (version == 3) {
    type = await input.u32();
    if (type == 0) throw RemoteException(RemoteErrorKind.protocol, await _reason(input));
  } else {
    final count = await input.u8();
    if (count == 0) throw RemoteException(RemoteErrorKind.protocol, await _reason(input));
    final offered = await input.read(count);
    final names = offered.map(securityTypeName).join(', ');
    type = offered.contains(none)
        ? none
        : offered.contains(vncAuth)
            ? vncAuth
            : throw RemoteException(RemoteErrorKind.unsupportedSecurity, names);
    log.info(src, 'Security types offered: $names → using ${securityTypeName(type)}');
    write([type]);
  }

  if (type == vncAuth) {
    final challenge = await input.read(16);
    final secret = await password();
    if (secret == null) throw const RemoteException(RemoteErrorKind.cancelled);
    write(vncAuthResponse(secret, challenge));
  } else if (type != none) {
    throw RemoteException(RemoteErrorKind.unsupportedSecurity, securityTypeName(type));
  }

  if (type == vncAuth || version == 8) {
    if (await input.u32() != 0) {
      throw RemoteException(RemoteErrorKind.vncAuthFailed, version == 8 ? await _reason(input) : null);
    }
    if (type == vncAuth) log.info(src, 'VNC password accepted');
  }

  write(const [1]); // ClientInit: shared session, don't kick other viewers
  final head = ByteData.sublistView(await input.read(24));
  final name = utf8.decode(await input.read(head.getUint32(20)), allowMalformed: true);
  log.info(
    src,
    'Desktop "$name" ${head.getUint16(0)}×${head.getUint16(2)}; server pixel format '
    '${head.getUint8(4)} bpp, depth ${head.getUint8(5)}, ${head.getUint8(6) == 0 ? 'little' : 'big'}-endian',
  );
  return ServerInit(head.getUint16(0), head.getUint16(2), name);
}

/// VNC authentication: DES-encrypt the challenge with the password as key,
/// each key byte bit-reversed (a historical quirk of the protocol).
Uint8List vncAuthResponse(String password, Uint8List challenge) {
  final key = Uint8List(8);
  final units = password.codeUnits;
  for (var i = 0; i < 8 && i < units.length; i++) {
    var b = units[i] & 0xff, r = 0;
    for (var bit = 0; bit < 8; bit++, b >>= 1) {
      r = (r << 1) | (b & 1);
    }
    key[i] = r;
  }
  return desEncrypt(key, challenge);
}

/// Single DES-ECB via 3DES with K1 = K2 = K3 (E∘D∘E collapses to E).
Uint8List desEncrypt(Uint8List key8, Uint8List data) {
  final engine = DESedeEngine()..init(true, KeyParameter(Uint8List.fromList([...key8, ...key8, ...key8])));
  final out = Uint8List(data.length);
  for (var o = 0; o < data.length; o += 8) {
    engine.processBlock(data, o, out, o);
  }
  return out;
}

Future<String> _reason(ByteReader input) async =>
    utf8.decode(await input.read(await input.u32()), allowMalformed: true);
