import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/providers.dart';
import '../../domain/entities/connection_profile.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

class RecentConnections extends ConsumerWidget {
  const RecentConnections({super.key, required this.onEdit});

  final ValueChanged<ConnectionProfile> onEdit;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profiles = ref.watch(profilesProvider);
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SectionLabel(l10n.recentTitle),
        if (profiles.isEmpty)
          Container(
            padding: const EdgeInsets.symmetric(vertical: 28),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.of(context).line),
            ),
            child: Text(
              l10n.recentEmpty,
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.of(context).muted),
            ),
          )
        else
          Card(
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                for (final (i, p) in profiles.indexed) ...[
                  if (i > 0) const Divider(indent: 72),
                  _ProfileTile(
                    profile: p,
                    onConnect: () => ref.read(sessionProvider.notifier).connect(p),
                    onEdit: () => onEdit(p),
                    onDelete: () => ref.read(profilesProvider.notifier).remove(p.id),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _ProfileTile extends StatefulWidget {
  const _ProfileTile({required this.profile, required this.onConnect, required this.onEdit, required this.onDelete});

  final ConnectionProfile profile;
  final VoidCallback onConnect, onEdit, onDelete;

  @override
  State<_ProfileTile> createState() => _ProfileTileState();
}

class _ProfileTileState extends State<_ProfileTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final p = widget.profile;
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final text = Theme.of(context).textTheme;
    final initial = p.displayName.characters.first.toUpperCase();
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onConnect,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Palette.clay.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(initial, style: text.titleMedium?.copyWith(color: Palette.clay, fontWeight: FontWeight.w600)),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.displayName, style: text.titleSmall, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(
                      [if (p.name.isNotEmpty) p.address, 'VNC ${p.vncHost}:${p.vncPort}', l10n.since(p.lastConnected)]
                          .join('  ·  '),
                      style: text.bodySmall?.copyWith(color: colors.muted),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                opacity: _hover ? 1 : 0,
                duration: const Duration(milliseconds: 120),
                child: Row(
                  children: [
                    IconButton(tooltip: l10n.edit, icon: const Icon(Icons.edit_outlined, size: 18), onPressed: widget.onEdit),
                    IconButton(
                      tooltip: l10n.delete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18),
                      onPressed: widget.onDelete,
                    ),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_rounded, size: 18, color: _hover ? Palette.clay : colors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
