import 'package:flutter/material.dart';

import '../../engine/cleaners/clean_target.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

export '../../engine/cleaners/clean_target.dart' show RiskLevel;

/// A compact, colour-coded verdict on how invasive a module is.
class RiskChip extends StatelessWidget {
  const RiskChip({required this.risk, super.key});

  final RiskLevel risk;

  Color _color(CyberPalette palette) {
    switch (risk) {
      case RiskLevel.safe:
        return palette.accent;
      case RiskLevel.moderate:
        return palette.warning;
      case RiskLevel.elevated:
        return palette.danger;
    }
  }

  String _label(AppLocalizations l10n) {
    switch (risk) {
      case RiskLevel.safe:
        return l10n.riskSafe;
      case RiskLevel.moderate:
        return l10n.riskModerate;
      case RiskLevel.elevated:
        return l10n.riskElevated;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    final color = _color(palette);
    final label = _label(AppLocalizations.of(context));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.7)),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: color,
              letterSpacing: context.tightTracking,
            ),
      ),
    );
  }
}

/// One selectable cleaning module: title, prose, size, risk and privilege.
class ModuleTile extends StatelessWidget {
  const ModuleTile({
    required this.title,
    required this.description,
    required this.sizeText,
    required this.risk,
    required this.selected,
    this.requiresPrivilege = false,
    this.onChanged,
    super.key,
  });

  final String title;
  final String description;
  final String sizeText;
  final RiskLevel risk;
  final bool selected;
  final bool requiresPrivilege;
  final ValueChanged<bool?>? onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    final l10n = AppLocalizations.of(context);
    final text = Theme.of(context).textTheme;

    return Semantics(
      container: true,
      selected: selected,
      label: '$title, $sizeText',
      child: Material(
        color:
            selected ? palette.accent.withValues(alpha: 0.08) : palette.surface,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onChanged == null ? null : () => onChanged!(!selected),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? palette.accent : palette.outline,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Checkbox(
                  value: selected,
                  onChanged: onChanged,
                  visualDensity: VisualDensity.compact,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: text.titleSmall?.copyWith(
                          color: palette.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        description,
                        style: text.bodySmall?.copyWith(
                          color: palette.textMuted,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          RiskChip(risk: risk),
                          if (requiresPrivilege)
                            Tooltip(
                              message: l10n.cleanerRequiresRoot,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color:
                                        palette.danger.withValues(alpha: 0.7),
                                  ),
                                  color: palette.danger.withValues(alpha: 0.12),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.lock_outline,
                                      size: 12,
                                      color: palette.danger,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      l10n.cleanerRequiresRoot,
                                      style: text.labelSmall?.copyWith(
                                        color: palette.danger,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  sizeText,
                  style: text.titleSmall?.copyWith(
                    color: palette.textPrimary,
                    fontFamily: 'monospace',
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
