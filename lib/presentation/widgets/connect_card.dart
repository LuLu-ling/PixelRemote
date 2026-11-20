import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/connection_profile.dart';
import '../../domain/entities/ssh_address.dart';
import '../../domain/errors.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';

/// Address bar plus optional advanced fields; builds a [ConnectionProfile]
/// and hands it to the session controller.
class ConnectCard extends ConsumerStatefulWidget {
  const ConnectCard({super.key, required this.editing, this.error});

  final ValueNotifier<ConnectionProfile?> editing;
  final RemoteException? error;

  @override
  ConsumerState<ConnectCard> createState() => _ConnectCardState();
}

class _ConnectCardState extends ConsumerState<ConnectCard> {
  final _address = TextEditingController();
  final _name = TextEditingController();
  final _vncHost = TextEditingController(text: 'localhost');
  final _vncPort = TextEditingController(text: '5900');
  final _identity = TextEditingController();
  final _start = TextEditingController();
  final _addressFocus = FocusNode();
  String? _editingId;
  bool _advanced = false;
  bool _invalid = false;

  @override
  void initState() {
    super.initState();
    widget.editing.addListener(_load);
  }

  @override
  void dispose() {
    widget.editing.removeListener(_load);
    for (final c in [_address, _name, _vncHost, _vncPort, _identity, _start]) {
      c.dispose();
    }
    _addressFocus.dispose();
    super.dispose();
  }

  void _load() {
    final p = widget.editing.value;
    if (p == null) return;
    setState(() {
      _editingId = p.id;
      _address.text = p.address;
      _name.text = p.name;
      _vncHost.text = p.vncHost;
      _vncPort.text = '${p.vncPort}';
      _identity.text = p.identityFile ?? '';
      _start.text = p.startCommand ?? '';
      _advanced = true;
      _invalid = false;
    });
    _addressFocus.requestFocus();
  }

  /// Reuses a saved profile for the same address unless the user is editing
  /// the advanced fields, so typing a known address keeps its settings.
  ConnectionProfile? _buildProfile() {
    final address = _address.text.trim();
    if (SshAddress.tryParse(address) == null) {
      setState(() => _invalid = true);
      return null;
    }
    final profiles = ref.read(profilesProvider);
    final existing = profiles.where((p) => p.id == _editingId).firstOrNull ??
        profiles.where((p) => p.address == address).firstOrNull;
    if (existing != null && !_advanced) return existing;
    String? optional(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    return ConnectionProfile(
      id: existing?.id ?? ConnectionProfile.newId(),
      address: address,
      name: _name.text.trim(),
      vncHost: optional(_vncHost) ?? 'localhost',
      vncPort: int.tryParse(_vncPort.text.trim()) ?? 5900,
      identityFile: optional(_identity),
      startCommand: optional(_start),
      lastConnected: existing?.lastConnected,
    );
  }

  void _connect() {
    final profile = _buildProfile();
    if (profile != null) ref.read(sessionProvider.notifier).connect(profile);
  }

  void _save() {
    final profile = _buildProfile();
    if (profile == null) return;
    ref.read(profilesProvider.notifier).upsert(profile);
    _editingId = profile.id;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.saved)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final error = widget.error;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    controller: _address,
                    focusNode: _addressFocus,
                    autofocus: true,
                    onSubmitted: (_) => _connect(),
                    onChanged: (_) => _invalid ? setState(() => _invalid = false) : null,
                    style: Theme.of(context).textTheme.titleMedium,
                    decoration: InputDecoration(
                      hintText: l10n.addressHint,
                      prefixIcon: const Icon(Icons.terminal_rounded),
                      errorText: _invalid ? l10n.errorInvalidAddress(_address.text.trim()) : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: _connect,
                  style: FilledButton.styleFrom(minimumSize: const Size(0, 54)),
                  icon: const Icon(Icons.arrow_forward_rounded, size: 18),
                  iconAlignment: IconAlignment.end,
                  label: Text(l10n.connect),
                ),
              ],
            ),
            if (error != null && error.kind != RemoteErrorKind.cancelled) ...[
              const SizedBox(height: 14),
              _ErrorBanner(message: l10n.error(error)),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() => _advanced = !_advanced),
                icon: AnimatedRotation(
                  turns: _advanced ? 0.25 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(Icons.chevron_right_rounded, color: colors.muted),
                ),
                label: Text(l10n.advanced, style: TextStyle(color: colors.muted)),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _advanced ? _advancedFields(l10n) : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }

  Widget _advancedFields(AppLocalizations l10n) {
    Widget field(TextEditingController c, String label, {String? hint, int flex = 1, bool digits = false}) => Expanded(
          flex: flex,
          child: TextField(
            controller: c,
            keyboardType: digits ? TextInputType.number : null,
            decoration: InputDecoration(labelText: label, hintText: hint),
          ),
        );
    const gap = SizedBox(width: 12, height: 12);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(children: [field(_name, l10n.displayName, hint: l10n.optional)]),
          gap,
          Row(children: [field(_vncHost, l10n.vncHost, flex: 3), gap, field(_vncPort, l10n.vncPort, digits: true)]),
          gap,
          Row(children: [field(_identity, l10n.identityFile, hint: l10n.identityFileHint)]),
          gap,
          Row(children: [field(_start, '${l10n.startCommand} · ${l10n.optional}', hint: l10n.startCommandHint)]),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.bookmark_add_outlined, size: 18),
              label: Text(l10n.save),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final danger = AppColors.of(context).danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: danger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: danger.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, color: danger, size: 20),
          const SizedBox(width: 10),
          Expanded(child: SelectableText(message, style: const TextStyle(height: 1.4))),
        ],
      ),
    );
  }
}
