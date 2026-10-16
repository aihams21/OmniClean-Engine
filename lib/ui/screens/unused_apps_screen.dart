import 'package:flutter/material.dart';

import '../../core/util/byte_fmt.dart';
import '../../engine/platform/storage_gateway.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../controllers/unused_apps_controller.dart';

/// The apps the device has not seen you open, with the size they cost you and
/// a deliberate tick before anything is removed.
class UnusedAppsScreen extends StatelessWidget {
  const UnusedAppsScreen({
    required this.controller,
    this.onGrantUsageAccess,
    super.key,
  });

  final UnusedAppsController controller;
  final VoidCallback? onGrantUsageAccess;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (BuildContext context, _) {
        return Column(
          children: <Widget>[
            _Header(
                controller: controller, onGrantUsageAccess: onGrantUsageAccess),
            const Divider(height: 1),
            Expanded(child: _body(context)),
          ],
        );
      },
    );
  }

  Widget _body(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.isBlind) {
      return _Centered(
        icon: Icons.lock_outline,
        title: l10n.unusedAppsBlind,
        color: CyberTheme.of(Theme.of(context)).warning,
      );
    }
    if (controller.phase == UnusedAppsPhase.failed) {
      return _Centered(
        icon: Icons.error_outline,
        title: l10n.unusedAppsFailed,
        color: CyberTheme.of(Theme.of(context)).danger,
      );
    }
    // "Nothing here" is only true once something has looked. Before that the
    // screen says it has not looked yet, because the difference between the
    // two is the difference between "you have no unused apps" and a lie.
    if (controller.phase == UnusedAppsPhase.idle) {
      return _Centered(text: l10n.unusedAppsIdle);
    }
    if (controller.isEmpty) {
      return _Centered(text: l10n.unusedAppsEmpty);
    }
    return _List(controller: controller);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, this.onGrantUsageAccess});

  final UnusedAppsController controller;
  final VoidCallback? onGrantUsageAccess;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String bytes(int value) =>
        formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            l10n.unusedAppsTitle,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          Text(
            l10n.unusedAppsSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              Text(
                l10n.unusedAppsThreshold,
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: palette.textMuted),
              ),
              for (final int days in controller.thresholdOptions)
                ChoiceChip(
                  label: Text('$days'),
                  selected: controller.thresholdDays == days,
                  onSelected: controller.isLoading
                      ? null
                      : (_) => controller.setThreshold(days),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              FilledButton.icon(
                onPressed: controller.isLoading ? null : controller.load,
                icon: controller.isLoading
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.search),
                label: Text(
                  controller.isLoading
                      ? l10n.unusedAppsRefreshing
                      : l10n.unusedAppsLoad,
                ),
              ),
              const SizedBox(width: 12),
              if (controller.isBlind)
                OutlinedButton.icon(
                  onPressed: onGrantUsageAccess ?? controller.requestAccess,
                  icon: const Icon(Icons.shield_outlined),
                  label: Text(l10n.unusedAppsGrant),
                ),
              if (controller.count > 0)
                Expanded(
                  child: Text(
                    l10n.unusedAppsCount(
                        controller.count, bytes(controller.totalBytes)),
                    textAlign: TextAlign.end,
                    style: Theme.of(context)
                        .textTheme
                        .labelLarge
                        ?.copyWith(color: palette.accent),
                  ),
                ),
            ],
          ),
          if (controller.selectedCount > 0) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              l10n.unusedAppsConfirmBody,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: palette.textMuted),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Text(
                  l10n.unusedAppsSelected(controller.selectedCount,
                      bytes(controller.selectedBytes)),
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: palette.textMuted),
                ),
                const Spacer(),
                TextButton(
                  onPressed:
                      controller.isLoading ? null : controller.selectNone,
                  child: Text(l10n.actionCancel),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  style:
                      FilledButton.styleFrom(backgroundColor: palette.danger),
                  onPressed:
                      controller.isLoading ? null : () => _uninstallSelected(),
                  icon: const Icon(Icons.delete_outline),
                  label: Text(l10n.unusedAppsRemoveSelected),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// Hands each ticked package to the platform's own uninstaller.
  ///
  /// No second confirmation dialog: Android already shows one per app, and a
  /// modal in front of it would be asking the same question twice. The user
  /// still confirms every single removal - just in the system's own voice.
  Future<void> _uninstallSelected() async {
    for (final String packageName in controller.selected) {
      await controller.uninstall(packageName);
    }
  }
}

class _List extends StatelessWidget {
  const _List({required this.controller});

  final UnusedAppsController controller;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
      itemCount: controller.apps.length,
      separatorBuilder: (BuildContext context, int index) =>
          const SizedBox(height: 10),
      itemBuilder: (BuildContext context, int index) => _Row(
        app: controller.apps[index],
        sizeText: formatBytes(
          controller.apps[index].sizeBytes,
          unitSystem: Localizations.localeOf(context).languageCode == 'ar'
              ? 'ar'
              : 'en',
        ),
        selected: controller.isSelected(controller.apps[index].packageName),
        canUninstall: controller.canUninstall,
        onChanged: (bool? value) {
          final String packageName = controller.apps[index].packageName;
          if (value ?? false) {
            controller.select(packageName);
          } else {
            controller.deselect(packageName);
          }
        },
        onUninstall: () =>
            controller.uninstall(controller.apps[index].packageName),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.app,
    required this.sizeText,
    required this.selected,
    required this.canUninstall,
    required this.onChanged,
    required this.onUninstall,
  });

  final AppUsage app;
  final String sizeText;
  final bool selected;
  final bool canUninstall;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final bool neverOpened = app.lastUsed.millisecondsSinceEpoch == 0;

    return Material(
      color: selected ? palette.elevated : palette.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => onChanged(!selected),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? palette.accent : palette.outline,
            ),
          ),
          child: Row(
            children: <Widget>[
              Checkbox(value: selected, onChanged: onChanged),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      app.label.isEmpty ? app.packageName : app.label,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    Text(
                      app.packageName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: palette.textMuted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      children: <Widget>[
                        // One tag, one fact. A never-opened app has no idle
                        // day count worth printing, and printing both would
                        // say the same thing twice.
                        if (neverOpened)
                          _Tag(
                            text: l10n.unusedAppsNeverOpened,
                            color: palette.warning,
                          )
                        else
                          _Tag(
                            text: l10n.unusedAppsIdleDays(app.unusedDays),
                            color: palette.info,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              Text(
                sizeText,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: palette.accent),
              ),
              const SizedBox(width: 6),
              if (canUninstall)
                IconButton(
                  tooltip: l10n.unusedAppsUninstall,
                  onPressed: onUninstall,
                  icon: const Icon(Icons.delete_outline),
                  color: palette.danger,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withValues(alpha: 0.7)),
          color: color.withValues(alpha: 0.12),
        ),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        ),
      );
}

class _Centered extends StatelessWidget {
  const _Centered({this.text, this.icon, this.title, this.color});

  final String? text;
  final IconData? icon;
  final String? title;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (icon != null) ...<Widget>[
              Icon(icon, size: 40, color: color ?? palette.textMuted),
              const SizedBox(height: 12),
            ],
            Text(
              text ?? title ?? '',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: color ?? palette.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
