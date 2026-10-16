import 'package:flutter/material.dart';

import '../../core/util/byte_fmt.dart';
import '../controllers/quarantine_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// The undo screen: everything OmniClean Engine has ever removed is listed
/// here with one tap back to where it came from.
class QuarantineScreen extends StatelessWidget {
  const QuarantineScreen({required this.controller, super.key});

  final QuarantineController controller;

  Future<void> _confirmPurgeAll(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.quarantinePurgeTitle),
        content: Text(l10n.quarantinePurgeBody(controller.count)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.danger),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.quarantinePurgeAll),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.purgeAll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final palette = CyberTheme.of(Theme.of(context));
        final arabic = Localizations.localeOf(context).languageCode == 'ar';
        String bytes(int value) =>
            formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.quarantineTitle,
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(
                    l10n.quarantineSubtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: palette.textMuted),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (controller.isBusy)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        Icon(Icons.shield_outlined,
                            size: 16, color: palette.accent),
                      const SizedBox(width: 8),
                      Text(
                        '${l10n.quarantineHolding(bytes(controller.totalBytes))}'
                        ' · ${l10n.quarantineItemCount(controller.count)}',
                        style: Theme.of(context)
                            .textTheme
                            .labelMedium
                            ?.copyWith(color: palette.accent),
                      ),
                      const Spacer(),
                      Text(
                        l10n.quarantineRetention(controller.retention.inDays),
                        style: Theme.of(context)
                            .textTheme
                            .labelSmall
                            ?.copyWith(color: palette.textMuted),
                      ),
                      const SizedBox(width: 8),
                      if (controller.hasExpired)
                        TextButton(
                          onPressed: controller.isBusy
                              ? null
                              : () => controller.purgeExpired(),
                          child: Text(l10n.actionPurge),
                        ),
                      OutlinedButton.icon(
                        onPressed: controller.isEmpty || controller.isBusy
                            ? null
                            : () => _confirmPurgeAll(context),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: palette.danger,
                          side: BorderSide(color: palette.danger),
                        ),
                        icon: const Icon(Icons.delete_forever, size: 18),
                        label: Text(l10n.quarantinePurgeAll),
                      ),
                    ],
                  ),
                  if (controller.hasExpired) ...[
                    const SizedBox(height: 6),
                    Text(
                      l10n.quarantineExpiredNote(controller.expiredCount),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.warning),
                    ),
                  ],
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: controller.isEmpty
                  ? Center(
                      child: Text(
                        l10n.quarantineEmpty,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: palette.textMuted),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(20),
                      itemCount: controller.count,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = controller.items[index];
                        return _Row(
                          key: ValueKey(item.id),
                          title: item.originalPath,
                          subtitle:
                                '${l10n.quarantineFrom(item.module)} · '
                                '${l10n.quarantineWhen(_when(item.quarantinedAt))}',
                          sizeText: bytes(item.bytes),
                          busy: controller.isBusy,
                          onRestore: () => controller.restore(item.id),
                          onPurge: () => controller.purge(item.id),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  static String _when(DateTime stamp) =>
      '${stamp.toLocal().year}-${_two(stamp.toLocal().month)}-'
      '${_two(stamp.toLocal().day)} '
      '${_two(stamp.toLocal().hour)}:${_two(stamp.toLocal().minute)}';

  static String _two(int value) => value.toString().padLeft(2, '0');
}

class _Row extends StatelessWidget {
  const _Row({
    required this.title,
    required this.subtitle,
    required this.sizeText,
    required this.busy,
    required this.onRestore,
    required this.onPurge,
    super.key,
  });

  final String title;
  final String subtitle;
  final String sizeText;
  final bool busy;
  final VoidCallback onRestore;
  final VoidCallback onPurge;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));

    return Material(
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.description_outlined, size: 18, color: palette.textMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontFamily: 'monospace', fontSize: 12),
                  ),
                  Text(
                    subtitle,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Text(
              sizeText,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: palette.accent),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: l10n.quarantineRestoreOne,
              onPressed: busy ? null : onRestore,
              icon: const Icon(Icons.restore, size: 18),
            ),
            IconButton(
              tooltip: l10n.quarantinePurgeOne,
              onPressed: busy ? null : onPurge,
              icon: Icon(Icons.delete_outline,
                  size: 18, color: palette.danger),
            ),
          ],
        ),
      ),
    );
  }
}
