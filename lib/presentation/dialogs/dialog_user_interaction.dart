import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../domain/services/platform_services.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';

/// [UserInteraction] answered with modal dialogs on the app's navigator.
final class DialogUserInteraction implements UserInteraction {
  DialogUserInteraction(this._navigator);

  final GlobalKey<NavigatorState> _navigator;

  BuildContext? get _context => _navigator.currentState?.overlay?.context;

  @override
  Future<String?> askSecret(SecretKind kind, String subject) async {
    final context = _context;
    if (context == null) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _SecretDialog(kind: kind, subject: subject),
    );
  }

  @override
  Future<bool> confirmHostKey({required String host, required String type, required String fingerprint}) async {
    final context = _context;
    if (context == null) return false;
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _HostKeyDialog(host: host, type: type, fingerprint: fingerprint),
    );
    return ok ?? false;
  }
}

class _SecretDialog extends StatefulWidget {
  const _SecretDialog({required this.kind, required this.subject});

  final SecretKind kind;
  final String subject;

  @override
  State<_SecretDialog> createState() => _SecretDialogState();
}

class _SecretDialogState extends State<_SecretDialog> {
  final _controller = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() => Navigator.of(context).pop(_controller.text);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final title = switch (widget.kind) {
      SecretKind.sshPassword => l10n.secretSshPassword,
      SecretKind.keyPassphrase => l10n.secretKeyPassphrase,
      SecretKind.vncPassword => l10n.secretVncPassword,
      SecretKind.challenge => l10n.secretChallenge,
    };
    return AlertDialog(
      icon: const Icon(Icons.lock_outline_rounded, color: Palette.clay),
      title: Text(title),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.secretFor(widget.subject), style: TextStyle(color: AppColors.of(context).muted)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              autofocus: true,
              obscureText: _obscure,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: Text(l10n.cancel)),
        FilledButton(onPressed: _submit, child: Text(l10n.ok)),
      ],
    );
  }
}

class _HostKeyDialog extends StatelessWidget {
  const _HostKeyDialog({required this.host, required this.type, required this.fingerprint});

  final String host, type, fingerprint;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    return AlertDialog(
      icon: const Icon(Icons.verified_user_outlined, color: Palette.clay),
      title: Text(l10n.hostKeyTitle),
      content: SizedBox(
        width: 440,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.hostKeyBody(host), style: TextStyle(color: colors.muted, height: 1.45)),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: colors.raised, borderRadius: BorderRadius.circular(12)),
              child: Row(
                children: [
                  Expanded(
                    child: SelectableText(
                      '$type\n$fingerprint',
                      style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    onPressed: () => Clipboard.setData(ClipboardData(text: fingerprint)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text(l10n.cancel)),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: Text(l10n.hostKeyTrust)),
      ],
    );
  }
}
