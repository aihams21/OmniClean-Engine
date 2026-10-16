import 'package:flutter/material.dart';

import '../../engine/shell.dart';
import '../controllers/settings_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/cyber_background.dart';

/// Appearance, language, safety and diagnostics.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({
    required this.controller,
    this.quarantinePath = '',
    this.version = '1.0.0',
    this.buildNumber = '1',
    this.onOpenLog,
    this.privilegeProbe = Shell.isRoot,
    super.key,
  });

  final SettingsController controller;
  final String quarantinePath;
  final String version;
  final String buildNumber;
  final VoidCallback? onOpenLog;

  /// How the screen answers "am I elevated?". Injectable so widget tests never
  /// spawn a real process (and never leave a pending timer behind).
  final Future<bool> Function() privilegeProbe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final settings = controller.settings;
        return CyberBackground(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              Text(l10n.settingsTitle,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 18),
              _Section(title: l10n.settingsAppearance),
              _Segmented(
                value: settings.accent,
                choices: {
                  AccentChoice.cyber: l10n.themeCyber,
                  AccentChoice.crimson: l10n.themeCrimson,
                },
                hints: {
                  AccentChoice.cyber: l10n.themeCyberHint,
                  AccentChoice.crimson: l10n.themeCrimsonHint,
                },
                onChanged: (value) => controller.setAccent(value),
              ),
              const SizedBox(height: 18),
              _Section(title: l10n.settingsLanguageSection),
              _Segmented<LanguageChoice>(
                value: settings.language,
                choices: {
                  LanguageChoice.system: l10n.langSystem,
                  LanguageChoice.english: l10n.langEnglish,
                  LanguageChoice.arabic: l10n.langArabic,
                },
                onChanged: (value) => controller.setLanguage(value),
              ),
              const SizedBox(height: 18),
              _Section(title: l10n.settingsSafety),
              _Slider(
                label: l10n.settingsMinAge,
                valueLabel: l10n.settingsMinAgeValue(settings.minAgeHours),
                hint: l10n.settingsMinAgeHint,
                value: settings.minAgeHours.toDouble(),
                max: SettingsController.maxMinAgeHours.toDouble(),
                onChanged: (value) => controller.setMinAgeHours(value.round()),
              ),
              const SizedBox(height: 14),
              _Slider(
                label: l10n.settingsRetention,
                valueLabel: l10n.quarantineRetention(settings.retentionDays),
                hint: l10n.settingsRetentionHint,
                value: settings.retentionDays.toDouble(),
                min: SettingsController.minRetentionDays.toDouble(),
                max: SettingsController.maxRetentionDays.toDouble(),
                onChanged: (value) =>
                    controller.setRetentionDays(value.round()),
              ),
              if (quarantinePath.isNotEmpty) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Icons.folder, size: 16, color: palette.textMuted),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${l10n.settingsQuarantinePath}: $quarantinePath',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 18),
              _Section(title: l10n.settingsDiagnostics),
              _RootAccess(probe: privilegeProbe),
              const SizedBox(height: 10),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: onOpenLog,
                  icon: const Icon(Icons.terminal, size: 18),
                  label: Text(l10n.settingsOpenLog),
                ),
              ),
              const SizedBox(height: 18),
              _Section(title: l10n.settingsAbout),
              Text(
                l10n.aboutHeadline,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                l10n.aboutBody,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: 10),
              Text(
                l10n.versionLabel(version, buildNumber),
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                    color: palette.textMuted),
              ),
              const SizedBox(height: 18),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  onPressed: controller.reset,
                  icon: const Icon(Icons.restart_alt, size: 18),
                  label: Text(l10n.settingsReset),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          letterSpacing: context.labelTracking,
          color: palette.accent,
          fontWeight: FontWeight.w700,
          fontFamilyFallback: AppTheme.fontFallbacks,
        ),
      ),
    );
  }
}

class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.value,
    required this.choices,
    required this.onChanged,
    this.hints = const {},
  });

  final T value;
  final Map<T, String> choices;
  final Map<T, String> hints;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SegmentedButton<T>(
          segments: [
            for (final entry in choices.entries)
              ButtonSegment<T>(
                value: entry.key,
                label: Text(entry.value),
                icon: entry.key == value
                    ? Icon(Icons.check, size: 14, color: palette.accent)
                    : null,
              ),
          ],
          selected: {value},
          showSelectedIcon: false,
          onSelectionChanged: (selection) => onChanged(selection.first),
        ),
        for (final entry in hints.entries)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              entry.value,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: palette.textMuted),
            ),
          ),
      ],
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.valueLabel,
    required this.hint,
    required this.value,
    required this.max,
    required this.onChanged,
    this.min = 0,
  });

  final String label;
  final String valueLabel;
  final String hint;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: Theme.of(context).textTheme.titleSmall),
            const Spacer(),
            Text(
              valueLabel,
              style: TextStyle(
                  fontFamily: 'monospace', fontSize: 12, color: palette.accent),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: ((max - min) / (max > 48 ? 24 : 1)).round().clamp(1, 60),
          label: valueLabel,
          onChanged: onChanged,
        ),
        Text(
          hint,
          style: Theme.of(context)
              .textTheme
              .labelSmall
              ?.copyWith(color: palette.textMuted),
        ),
      ],
    );
  }
}

class _RootAccess extends StatefulWidget {
  const _RootAccess({required this.probe});

  final Future<bool> Function() probe;

  @override
  State<_RootAccess> createState() => _RootAccessState();
}

class _RootAccessState extends State<_RootAccess> {
  bool? _root;

  @override
  void initState() {
    super.initState();
    _probe();
  }

  Future<void> _probe() async {
    final bool root = await widget.probe();
    if (mounted) setState(() => _root = root);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final bool? root = _root;

    return Row(
      children: [
        Icon(
          root == true ? Icons.lock_open : Icons.lock_outline,
          size: 16,
          color: root == true ? palette.accent : palette.textMuted,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                root == null
                    ? '…'
                    : root
                        ? l10n.rootAvailable
                        : l10n.rootUnavailable,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (root == false)
                Text(
                  l10n.rootUnavailableHint,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: palette.textMuted),
                ),
            ],
          ),
        ),
        IconButton(
          onPressed: _probe,
          icon: const Icon(Icons.refresh, size: 18),
        ),
      ],
    );
  }
}
