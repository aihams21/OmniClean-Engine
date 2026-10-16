import 'package:flutter/material.dart';

import '../../core/util/byte_fmt.dart';
import '../controllers/cleaner_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/module_tile.dart';
import 'target_strings.dart';

/// The interactive review list: every declared target, what it found, and a
/// deliberate tick before anything is removed.
class CleanerScreen extends StatelessWidget {
  const CleanerScreen({required this.controller, super.key});

  final CleanerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final arabic = Localizations.localeOf(context).languageCode == 'ar';
        String bytes(int value) =>
            formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

        return Column(
          children: [
            _Header(controller: controller),
            const Divider(height: 1),
            Expanded(
              child: !controller.hasScanned
                  ? _Idle(message: l10n.cleanerNothingScanned)
                  : ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            TextButton(
                              onPressed: controller.isBusy
                                  ? null
                                  : controller.selectAll,
                              child: Text(l10n.cleanerSelectAll),
                            ),
                            TextButton(
                              onPressed: controller.isBusy
                                  ? null
                                  : controller.selectNone,
                              child: Text(l10n.cleanerSelectNone),
                            ),
                            const Spacer(),
                            if (controller.selectedFiles > 0)
                              Text(
                                l10n.dashboardFilesCount(
                                    controller.selectedFiles),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelMedium
                                    ?.copyWith(
                                        color:
                                            CyberTheme.of(Theme.of(context)).textMuted),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        for (final module in controller.modules)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: ModuleTile(
                              title: l10n.targetTitle(module.target.titleKey),
                              description: l10n.targetDescription(
                                  module.target.descriptionKey),
                              sizeText: bytes(module.bytes),
                              risk: module.target.risk,
                              selected: module.selected,
                              requiresPrivilege:
                                  module.target.requiresPrivilege,
                              onChanged: controller.isBusy
                                  ? null
                                  : (_) => controller.toggle(module.target.id),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final CleanerController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String bytes(int value) =>
        formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.cleanerTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          Text(
            l10n.cleanerSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: controller.isBusy ? null : () => controller.scan(),
                icon: controller.isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar),
                label: Text(controller.hasScanned
                    ? l10n.cleanerRescan
                    : l10n.cleanerScanAll),
              ),
              const SizedBox(width: 12),
              FilledButton.tonalIcon(
                onPressed: controller.canClean ? () => _confirm(context) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: controller.canClean
                      ? palette.accent
                      : palette.elevated,
                ),
                icon: const Icon(Icons.auto_fix_high),
                label: Text(
                  '${l10n.cleanerCleanSelected} · ${bytes(controller.selectedBytes)}',
                ),
              ),
              const SizedBox(width: 12),
              if (controller.isBusy)
                TextButton(
                  onPressed: controller.cancelScan,
                  child: Text(l10n.actionCancel),
                ),
            ],
          ),
          if (controller.isBusy) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: controller.progressTotal == 0
                  ? null
                  : controller.progressDone / controller.progressTotal,
            ),
            const SizedBox(height: 6),
            Text(
              l10n.cleanerProgress(
                  controller.progressDone, controller.progressTotal),
              style:
                  Theme.of(context).textTheme.labelSmall?.copyWith(color: palette.textMuted),
            ),
          ],
          if (controller.bytesFreed > 0) ...[
            const SizedBox(height: 12),
            Text(
              l10n.cleanerResultBody(
                  bytes(controller.bytesFreed), controller.filesCleaned),
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.accent),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String bytes(int value) =>
        formatBytes(value, unitSystem: arabic ? 'ar' : 'en');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.cleanerConfirmTitle),
        content: Text(l10n.cleanerConfirmBody(
            controller.selectedFiles, bytes(controller.selectedBytes))),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.accent),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.cleanerConfirmProceed),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.cleanSelected();
    }
  }
}

class _Idle extends StatelessWidget {
  const _Idle({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          message,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: CyberTheme.of(Theme.of(context)).textMuted),
        ),
      );
}
