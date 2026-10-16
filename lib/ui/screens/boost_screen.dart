import 'package:flutter/material.dart';

import '../../engine/boost/boost_plan.dart';
import '../controllers/boost_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// Localised copy for one boost step.
///
/// The plan carries ARB *keys* rather than strings so the engine stays free of
/// Flutter's localisation layer and can be tested as plain data.
extension BoostLabels on AppLocalizations {
  String actionTitle(String key) => switch (key) {
        'boostActionAndroidTitle' => boostActionAndroidTitle,
        'boostActionPowerPlanTitle' => boostActionPowerPlanTitle,
        'boostActionWorkingSetsTitle' => boostActionWorkingSetsTitle,
        'boostActionIndexerTitle' => boostActionIndexerTitle,
        'boostActionGovernorTitle' => boostActionGovernorTitle,
        'boostActionSwappinessTitle' => boostActionSwappinessTitle,
        'boostActionDropCachesTitle' => boostActionDropCachesTitle,
        'boostActionTrimTitle' => boostActionTrimTitle,
        _ => key,
      };

  String actionDescription(String key) => switch (key) {
        'boostActionAndroidDescription' => boostActionAndroidDescription,
        'boostActionPowerPlanDescription' => boostActionPowerPlanDescription,
        'boostActionWorkingSetsDescription' =>
          boostActionWorkingSetsDescription,
        'boostActionIndexerDescription' => boostActionIndexerDescription,
        'boostActionGovernorDescription' => boostActionGovernorDescription,
        'boostActionSwappinessDescription' => boostActionSwappinessDescription,
        'boostActionDropCachesDescription' => boostActionDropCachesDescription,
        'boostActionTrimDescription' => boostActionTrimDescription,
        _ => '',
      };

  String impact(BoostImpact value) => switch (value) {
        BoostImpact.frames => boostImpactFrames,
        BoostImpact.memory => boostImpactMemory,
        BoostImpact.latency => boostImpactLatency,
        BoostImpact.storage => boostImpactStorage,
      };
}

/// One screen, one button, one honest report.
///
/// The screen never says "done" on its own: it says how many steps the machine
/// actually applied, and prints the system's own answer for every step that
/// refused. A boost that silently does nothing is worse than no boost at all.
class BoostScreen extends StatelessWidget {
  const BoostScreen({required this.controller, super.key});

  final BoostController controller;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        children: [
          _Header(controller: controller),
          const Divider(height: 1),
          Expanded(
            child: controller.actions.isEmpty
                ? _Centered(
                    text: AppLocalizations.of(context).boostNothingAvailable)
                : ListView(
                    padding: const EdgeInsets.all(20),
                    children: <Widget>[
                      if (controller.phase == BoostPhase.done) ...[
                        _Report(controller: controller),
                        const SizedBox(height: 16),
                      ],
                      for (final BoostAction action in controller.actions)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _Step(
                            action: action,
                            result: controller.resultFor(action.id),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller});

  final BoostController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(l10n.boostTitle,
              style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            l10n.boostSubtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: palette.textMuted),
          ),
          const SizedBox(height: 16),
          // A button that cannot do anything is a lie in the shape of a
          // control. With no steps to run there is no button at all.
          if (controller.actions.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: controller.canRun ? controller.run : null,
                icon: controller.isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.bolt),
                label: Text(
                  controller.isBusy
                      ? l10n.boostRunning
                      : controller.phase == BoostPhase.done
                          ? l10n.boostRerun
                          : l10n.boostRun,
                ),
              ),
            ),
          if (controller.isBusy && controller.progressTotal > 0) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: controller.progressDone / controller.progressTotal,
            ),
          ],
        ],
      ),
    );
  }
}

class _Report extends StatelessWidget {
  const _Report({required this.controller});

  final BoostController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));

    if (!controller.didAnything) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: palette.danger.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.danger.withValues(alpha: 0.6)),
        ),
        child: Text(
          l10n.boostNothingChanged,
          style: Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(color: palette.danger),
        ),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.accent.withValues(alpha: 0.6)),
      ),
      child: Text(
        l10n.boostResultHeadline(
            controller.succeededCount, controller.progressTotal),
        style: Theme.of(context)
            .textTheme
            .titleSmall
            ?.copyWith(color: palette.accent),
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.action, required this.result});

  final BoostAction action;
  final BoostActionResult? result;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final Color tone = result == null
        ? palette.textMuted
        : (result!.ok ? palette.accent : palette.danger);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            result == null
                ? Icons.radio_button_unchecked
                : (result!.ok ? Icons.check_circle : Icons.cancel),
            color: tone,
            size: 20,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  l10n.actionTitle(action.titleKey),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 2),
                Text(
                  l10n.actionDescription(action.descriptionKey),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: palette.textMuted),
                ),
                if (result != null && result!.detail.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    result!.detail,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      color: tone,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                l10n.impact(action.impact),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tone),
              ),
              if (action.requiresPrivilege)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Tooltip(
                    message: l10n.boostRequiresPrivilege,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Icon(Icons.lock_outline,
                            size: 12, color: palette.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          l10n.boostRequiresPrivilege,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(color: palette.textMuted),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: CyberTheme.of(Theme.of(context)).textMuted),
          ),
        ),
      );
}
