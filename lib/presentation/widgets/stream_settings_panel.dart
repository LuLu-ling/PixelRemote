import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/controllers.dart';
import '../../application/providers.dart';
import '../../domain/entities/keyboard.dart';
import '../../domain/entities/stream_settings.dart';
import '../l10n.dart';
import '../theme/app_theme.dart';
import 'common.dart';

/// Quality, frame rate, colour depth, bandwidth and key mapping.
/// Edits preferences; a live session follows them immediately.
class StreamSettingsPanel extends ConsumerWidget {
  const StreamSettingsPanel({super.key, required this.title, required this.onClose});

  final String title;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final colors = AppColors.of(context);
    final prefs = ref.watch(preferencesProvider);
    final session = ref.watch(sessionProvider);
    final remapper = ref.watch(keyRemapperProvider);
    final update = ref.read(preferencesProvider.notifier).update;
    final s = prefs.stream;
    void set(StreamSettings next) => update((p) => p.copyWith(stream: next));
    final hint = TextStyle(color: colors.muted, fontSize: 12, height: 1.4);
    const gap = SizedBox(height: 22);

    return SizedBox(
      width: 380,
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(22, 18, 14, 22),
        children: [
          Row(
            children: [
              Expanded(child: Text(title, style: Theme.of(context).textTheme.headlineSmall)),
              IconButton(tooltip: l10n.close, icon: const Icon(Icons.close_rounded), onPressed: onClose),
            ],
          ),
          const SizedBox(height: 14),
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(l10n.quality),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final q in ImageQuality.values)
                      ChoiceChip(
                        label: Text(l10n.qualityName(q)),
                        selected: s.quality == q,
                        onSelected: (_) => set(s.copyWith(quality: q)),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(s.quality == ImageQuality.auto ? l10n.qualityAutoHint : l10n.qualityFixedHint, style: hint),
                if (ref.watch(sessionStatsProvider).value?.encoding case final enc? when enc == 'ZRLE' || enc == 'Raw') ...[
                  const SizedBox(height: 8),
                  Text(l10n.qualityNoEffect(enc), style: hint),
                ],
                gap,
                SectionLabel(l10n.frameRate, trailing: Text(l10n.fps(s.frameRate), style: hint)),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final f in StreamSettings.frameRates)
                      ChoiceChip(
                        label: Text('$f'),
                        selected: s.frameRate == f,
                        onSelected: (_) => set(s.copyWith(frameRate: f)),
                      ),
                  ],
                ),
                gap,
                SectionLabel(l10n.colorDepth),
                SegmentedButton<ColorDepth>(
                  showSelectedIcon: false,
                  segments: [for (final d in ColorDepth.values) ButtonSegment(value: d, label: Text(l10n.depth(d)))],
                  selected: {s.colorDepth},
                  onSelectionChanged: (v) => set(s.copyWith(colorDepth: v.first)),
                ),
                gap,
                SectionLabel(l10n.bandwidth),
                Select<int>(
                  value: s.maxBandwidthMbps,
                  items: StreamSettings.bandwidthLimits,
                  label: l10n.bandwidthLimit,
                  onChanged: (v) => set(s.copyWith(maxBandwidthMbps: v)),
                ),
                const SizedBox(height: 8),
                Text(l10n.bandwidthHint, style: hint),
                gap,
                SectionLabel(l10n.keyMapping),
                Select<KeyMappingMode>(
                  value: prefs.keyMapping,
                  items: KeyMappingMode.values,
                  label: l10n.mapping,
                  onChanged: (m) => update((p) => p.copyWith(keyMapping: m)),
                ),
                if (session is SessionActive) ...[
                  const SizedBox(height: 8),
                  Text(
                    l10n.mappingActive(
                      l10n.mapping(remapper.effective),
                      l10n.os(ref.watch(localPlatformProvider).os),
                      l10n.os(session.session.remoteOs),
                    ),
                    style: hint,
                  ),
                ],
                const SizedBox(height: 14),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.showStats),
                  value: prefs.showStats,
                  onChanged: (v) => update((p) => p.copyWith(showStats: v)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
