import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/util/byte_fmt.dart';
import '../../core/util/logger.dart';
import '../../engine/metrics/metrics_collector.dart';
import '../../engine/metrics/system_snapshot.dart';
import '../controllers/cleaner_controller.dart';
import '../controllers/quarantine_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/arc_gauge.dart';
import '../widgets/storage_bar.dart';

/// Live health plus a single honest answer to "how much can I get back?".
///
/// [SystemMetricsService] is a stream, not a `Listenable`, so this screen owns
/// the subscription itself and only rebuilds the gauges it actually shows.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    required this.metrics,
    required this.cleaner,
    required this.quarantine,
    required this.onOpenCleaner,
    super.key,
  });

  final SystemMetricsService metrics;
  final CleanerController cleaner;
  final QuarantineController quarantine;
  final VoidCallback onOpenCleaner;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  StreamSubscription<SystemSnapshot>? _subscription;
  SystemSnapshot? _snapshot;

  @override
  void initState() {
    super.initState();
    _snapshot = widget.metrics.latest;
    _subscription = widget.metrics.snapshots.listen((snapshot) {
      if (mounted) {
        setState(() => _snapshot = snapshot);
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String bytes(int value) => formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

    return AnimatedBuilder(
      animation: Listenable.merge([widget.cleaner, widget.quarantine]),
      builder: (context, _) {
        final cleaner = widget.cleaner;
        final snapshot =
            _snapshot ?? SystemSnapshot.empty(MetricsPlatform.unsupported);
        final disk = snapshot.tightestDisk;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(l10n.dashboardTitle,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 4),
            Text(
              l10n.dashboardSubtitle,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 24),
            _Gauges(snapshot: snapshot),
            const SizedBox(height: 20),
            if (snapshot.hasDisks && disk != null) ...[
              _Card(
                title: l10n.dashboardStorage,
                trailing: l10n.dashboardStorageFree(
                  bytes(disk.freeBytes),
                  bytes(disk.totalBytes),
                ),
                child: StorageBar(
                  usedBytes: disk.usedBytes,
                  freeBytes: disk.freeBytes,
                ),
              ),
              const SizedBox(height: 16),
            ],
            _Card(
              title: l10n.dashboardReclaimable,
              value: bytes(cleaner.totalBytes),
              subtitle: cleaner.hasScanned
                  ? l10n.dashboardFilesCount(cleaner.totalFiles)
                  : l10n.dashboardNothingScanned,
              trailing: cleaner.bytesFreed > 0
                  ? '${l10n.cleanerDone} · ${bytes(cleaner.bytesFreed)}'
                  : null,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: cleaner.isBusy ? null : () => cleaner.scan(),
                  icon: const Icon(Icons.radar),
                  label: Text(l10n.dashboardScanAll),
                ),
                OutlinedButton.icon(
                  onPressed:
                      cleaner.canClean ? () => widget.onOpenCleaner() : null,
                  icon: const Icon(Icons.auto_fix_high),
                  label: Text(
                    '${l10n.dashboardCleanSelected} (${bytes(cleaner.selectedBytes)})',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            const _ActivityLog(),
          ],
        );
      },
    );
  }
}

class _Gauges extends StatelessWidget {
  const _Gauges({required this.snapshot});

  final SystemSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final live = snapshot.isLive;
    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: [
        ArcGauge(
          label: l10n.gaugeCpu,
          value: live ? snapshot.cpuUsage : null,
          color: palette.accent,
        ),
        ArcGauge(
          label: l10n.gaugeMemory,
          value: live ? snapshot.memory.usedFraction : null,
          color: palette.info,
        ),
        ArcGauge(
          label: l10n.gaugeSwap,
          value: live && snapshot.memory.swapTotalBytes > 0
              ? snapshot.memory.swapUsedFraction
              : null,
          color: palette.warning,
        ),
      ],
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    this.child,
    this.value,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final Widget? child;
  final String? value;
  final String? subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.outline),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: palette.textMuted,
                        letterSpacing: context.labelTracking,
                      ),
                ),
              ),
              if (trailing != null)
                Text(
                  trailing!,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: palette.accent),
                ),
            ],
          ),
          if (value != null) ...[
            const SizedBox(height: 6),
            Text(
              value!,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: palette.accent,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
            ),
          ],
          if (subtitle != null) ...[
            const SizedBox(height: 2),
            Text(
              subtitle!,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          if (child != null) ...[const SizedBox(height: 14), child!],
        ],
      ),
    );
  }
}

class _ActivityLog extends StatefulWidget {
  const _ActivityLog();
  @override
  State<_ActivityLog> createState() => _ActivityLogState();
}

class _ActivityLogState extends State<_ActivityLog> {
  late final List<String> _lines = List<String>.of(log.recent);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    return _Card(
      title: l10n.dashboardActivityLog,
      child: _lines.isEmpty
          ? Text(
              l10n.dashboardLogEmpty,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.textMuted),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final line in _lines.reversed.take(12))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 1),
                    child: Text(
                      line,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: palette.textMuted,
                            fontFamily: 'monospace',
                            fontSize: 12,
                          ),
                    ),
                  ),
              ],
            ),
    );
  }
}
