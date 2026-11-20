import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pixel_remote/data/ssh/known_hosts_verifier.dart';
import 'package:pixel_remote/data/ssh/ssh_config_resolver.dart';
import 'package:pixel_remote/domain/entities/keyboard.dart';
import 'package:pixel_remote/domain/entities/ssh_address.dart';
import 'package:pixel_remote/domain/services/platform_services.dart';
import 'package:pointycastle/export.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

final class _Platform implements LocalPlatform {
  @override
  HostOs get os => HostOs.linux;
  @override
  String get homeDirectory => '/home/me';
  @override
  String get userName => 'me';
  @override
  String? get agentSocket => '/tmp/agent.sock';
}

void main() {
  group('SshConfigResolver', () {
    const config = '''
# global defaults
Host work-*
  User deploy
  IdentityFile ~/.ssh/work_key

Host work-db !work-db-old
  HostName 10.1.2.3
  Port 2200

Host *
  User fallback
  IdentityAgent none
  Port 22
''';
    final resolver = SshConfigResolver(_Platform(), configText: config);

    test('applies the first matching value per option', () {
      final e = resolver.resolve(const SshAddress(host: 'work-db'));
      expect((e.host, e.port, e.user), ('10.1.2.3', 2200, 'deploy'));
      expect(e.identityFiles.first, '/home/me/.ssh/work_key');
      expect(e.identityFiles, contains('/home/me/.ssh/id_ed25519'));
      expect(e.agentSocket, isNull, reason: 'IdentityAgent none');
    });

    test('negated patterns exclude a host; explicit user and port win', () {
      final e = resolver.resolve(const SshAddress(host: 'work-db-old', user: 'root', port: 8022));
      expect((e.host, e.port, e.user), ('work-db-old', 8022, 'root'));
    });

    test('falls back to the local user and default keys', () {
      final e = SshConfigResolver(_Platform(), configText: '').resolve(const SshAddress(host: 'box'));
      expect((e.host, e.port, e.user, e.agentSocket), ('box', 22, 'me', '/tmp/agent.sock'));
      expect(e.identityFiles, hasLength(3));
    });
  });

  group('KnownHostsVerifier', () {
    late SharedPreferencesWithCache prefs;
    final key = Uint8List.fromList(utf8.encode('fake-ed25519-key-blob'));
    final fingerprint = KnownHostsVerifier.fingerprintOf(key);

    setUp(() async {
      SharedPreferencesAsyncPlatform.instance = InMemorySharedPreferencesAsync.empty();
      prefs = await SharedPreferencesWithCache.create(cacheOptions: const SharedPreferencesWithCacheOptions());
    });

    String hashed(String host) {
      final salt = Uint8List.fromList(List.generate(20, (i) => i));
      final mac = HMac(SHA1Digest(), 64)..init(KeyParameter(salt));
      return '|1|${base64.encode(salt)}|${base64.encode(mac.process(utf8.encode(host)))}';
    }

    test('trusts plain and hashed OpenSSH entries, flags changed keys', () async {
      final knownHosts = [
        'plain.example ssh-ed25519 ${base64.encode(key)}',
        '${hashed('[hashed.example]:2222')} ssh-ed25519 ${base64.encode(key)}',
        'changed.example ssh-ed25519 ${base64.encode(utf8.encode('other'))}',
      ].join('\n');
      final v = KnownHostsVerifier(prefs, '/nowhere', knownHostsText: knownHosts);
      expect(await v.check('plain.example', 22, 'ssh-ed25519', fingerprint), HostKeyStatus.trusted);
      expect(await v.check('hashed.example', 2222, 'ssh-ed25519', fingerprint), HostKeyStatus.trusted);
      expect(await v.check('changed.example', 22, 'ssh-ed25519', fingerprint), HostKeyStatus.changed);
      expect(await v.check('changed.example', 22, 'rsa-sha2-512', fingerprint), HostKeyStatus.unknown,
          reason: 'a different key family is not a change');
      expect(await v.check('new.example', 22, 'ssh-ed25519', fingerprint), HostKeyStatus.unknown);
    });

    test('remembers keys the user trusted', () async {
      final v = KnownHostsVerifier(prefs, '/nowhere', knownHostsText: '');
      await v.trust('new.example', 22, 'ssh-ed25519', fingerprint);
      expect(await v.check('new.example', 22, 'ssh-ed25519', fingerprint), HostKeyStatus.trusted);
      expect(await v.check('new.example', 22, 'ssh-ed25519', 'SHA256:different'), HostKeyStatus.changed);
    });
  });
}
