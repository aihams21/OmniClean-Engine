import 'package:flutter/material.dart';

import '../../core/util/byte_fmt.dart';
import '../../engine/duplicates/duplicate_finder.dart';
import '../controllers/duplicates_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Interactive review list for the SHA-256 duplicate finder.
///
/// Nothing is ever deleted from here on a single tap: a group must be ticked,
/// the oldest copy is always kept, and the confirm dialog states the exact
/// count and size that will move into quarantine.
class DuplicatesScreen extends StatelessWidget {
  const DuplicatesScreen({required this.controller, super.key});

  final DuplicatesController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        return Column(
          children: [
            _Header(controller: controller),
            const Divider(height: 1),
            Expanded(child: _Roots(controller: controller)),
            if (controller.groups.isNotEmpty)
              _ActionBar(controller: controller),
          ],
        );
      },
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final DuplicatesController controller;

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
          Text(l10n.duplicatesTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          Text(
            l10n.duplicatesSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              FilledButton.icon(
                onPressed: controller.canScan ? () => controller.scan() : null,
                icon: controller.isScanning
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.fingerprint),
                label: Text(l10n.duplicatesFind),
              ),
              const SizedBox(width: 12),
              if (controller.isScanning)
                TextButton(
                  onPressed: controller.cancelScan,
                  child: Text(l10n.duplicatesCancelScan),
                ),
              const Spacer(),
              if (controller.groups.isNotEmpty)
                Text(
                  l10n.duplicatesSummary(
                      controller.groups.length, bytes(controller.wastedBytes)),
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(color: palette.accent),
                ),
            ],
          ),
          if (controller.isScanning) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: controller.progressTotal == 0
                  ? null
                  : controller.progressDone / controller.progressTotal,
            ),
            const SizedBox(height: 6),
            Text(
              _phaseLabel(l10n, controller.hashPhase),
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ],
          if (controller.wasCancelled) ...[
            const SizedBox(height: 8),
            Text(
              l10n.dashboardCancelled,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.warning),
            ),
          ],
        ],
      ),
    );
  }

  static String _phaseLabel(AppLocalizations l10n, HashPhase? phase) {
    switch (phase) {
      case HashPhase.walking:
        return l10n.duplicatesPhaseWalking;
      case HashPhase.preFiltering:
        return l10n.duplicatesPhasePreFiltering;
      case HashPhase.hashing:
        return l10n.duplicatesPhaseHashing;
      case HashPhase.done:
        return l10n.duplicatesPhaseDone;
      case null:
        return l10n.duplicatesPhaseWalking;
    }
  }
}

class _Roots extends StatefulWidget {
  const _Roots({required this.controller});

  final DuplicatesController controller;

  @override
  State<_Roots> createState() => _RootsState();
}

class _RootsState extends State<_Roots> {
  final TextEditingController _field = TextEditingController();

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _add() {
    widget.controller.addRoot(_field.text);
    _field.clear();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final controller = widget.controller;

    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      children: [
        Text(l10n.duplicatesRoots,
            style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 4),
        Text(
          l10n.duplicatesRootHint,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: palette.textMuted),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _field,
                onSubmitted: (_) => _add(),
                style: const TextStyle(fontFamily: 'monospace'),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.folder_open, size: 18),
                  hintText: '/home/user/Downloads',
                ),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: Text(l10n.duplicatesAddRoot),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (controller.roots.isEmpty)
          Text(
            l10n.duplicatesNoRoots,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: palette.textMuted),
          )
        else
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final root in controller.roots)
                InputChip(
                  label: Text(root,
                      style: const TextStyle(fontFamily: 'monospace')),
                  onDeleted: controller.isScanning
                      ? null
                      : () => controller.removeRoot(root),
                ),
            ],
          ),
        const SizedBox(height: 18),
        if (controller.groups.isEmpty)
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Text(
                l10n.duplicatesSummary(0, '0'),
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: palette.textMuted),
              ),
            ),
          )
        else
          for (final group in controller.groups)
            _GroupCard(
              group: group,
              selected: controller.selectedPaths.contains(
                controller.deletablePathsFor(group.sha256).firstOrNull ?? '',
              ),
              onToggle: () => controller.selectGroup(group.sha256),
            ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.selected,
    required this.onToggle,
  });

  final DuplicateGroup group;
  final bool selected;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String bytes(int value) =>
        formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

    final keep = group.keepSuggestion;
    final sha = group.sha256;
    final prefix = sha.length <= 12 ? sha : sha.substring(0, 12);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: selected ? palette.accent.withValues(alpha: 0.08) : null,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank,
                      size: 20,
                      color: selected ? palette.accent : palette.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      l10n.duplicatesCopies(group.files.length),
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      bytes(group.wastedBytes),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(color: palette.accent),
                    ),
                    const Spacer(),
                    Text(
                      l10n.duplicatesHashPrefix(prefix),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 11,
                      ).copyWith(color: palette.textMuted),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                for (final file in group.files)
                  Padding(
                    padding: const EdgeInsets.only(left: 30, top: 4),
                    child: Row(
                      children: [
                        Icon(
                          file.path == keep?.path
                              ? Icons.star
                              : Icons.insert_drive_file_outlined,
                          size: 14,
                          color: file.path == keep?.path
                              ? palette.accent
                              : palette.textMuted,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            file.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: file.path == keep?.path
                                  ? palette.textPrimary
                                  : palette.textMuted,
                            ),
                          ),
                        ),
                        Text(
                          bytes(file.sizeBytes),
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Text(
                    keep == null ? '' : '${l10n.duplicatesKeep}: ${keep.name}',
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: palette.textMuted),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({required this.controller});

  final DuplicatesController controller;

  Future<void> _confirm(BuildContext context) async {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.duplicatesConfirmTitle(controller.selectedCount)),
        content: Text(l10n.duplicatesConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.actionCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: palette.accent),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.duplicatesDeleteDuplicates),
          ),
        ],
      ),
    );
    if (confirmed ?? false) {
      await controller.deleteSelected();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));

    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(top: BorderSide(color: palette.outline)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
      child: Row(
        children: [
          Text(
            l10n.duplicatesSelectedCount(controller.selectedCount),
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: palette.textMuted),
          ),
          const Spacer(),
          TextButton(
            onPressed: controller.isScanning ? null : controller.selectAll,
            child: Text(l10n.cleanerSelectAll),
          ),
          TextButton(
            onPressed: controller.isScanning ? null : controller.selectNone,
            child: Text(l10n.cleanerSelectNone),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: controller.canDelete ? () => _confirm(context) : null,
            icon: const Icon(Icons.delete_sweep),
            label: Text(l10n.duplicatesDeleteDuplicates),
          ),
        ],
      ),
    );
  }
}
