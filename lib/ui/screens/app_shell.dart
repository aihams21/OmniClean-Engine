import 'package:flutter/material.dart';

import '../../core/util/logger.dart';
import '../../engine/shell.dart';
import '../controllers/cleaner_controller.dart';
import '../controllers/duplicates_controller.dart';
import '../controllers/library_controller.dart';
import '../controllers/unused_apps_controller.dart';
import '../controllers/boost_controller.dart';
import '../controllers/quarantine_controller.dart';
import '../controllers/settings_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';
import '../widgets/cyber_background.dart';
import '../../engine/metrics/metrics_collector.dart';
import 'cleaner_screen.dart';
import 'library_screen.dart';
import 'dashboard_screen.dart';
import 'duplicates_screen.dart';
import 'quarantine_screen.dart';
import 'settings_screen.dart';
import 'unused_apps_screen.dart';
import 'boost_screen.dart';

/// The frame around every screen: the accent-aware background, the navigation
/// and the single source of truth for which page is on screen.
///
/// Navigation adapts to the window: a [NavigationRail] on desktop, a
/// [NavigationBar] on a phone. Both are built from the same list, so a new
/// page cannot appear in one layout and be missing from the other.
class AppShell extends StatefulWidget {
  const AppShell({
    required this.settings,
    required this.metrics,
    required this.cleaner,
    required this.duplicates,
    required this.quarantine,
    required this.library,
    required this.apps,
    required this.boost,
    this.version = '1.0.0',
    this.buildNumber = '1',
    this.privilegeProbe = Shell.isRoot,
    super.key,
  });

  final SettingsController settings;
  final SystemMetricsService metrics;
  final CleanerController cleaner;
  final DuplicatesController duplicates;
  final QuarantineController quarantine;
  final LibraryController library;
  final UnusedAppsController apps;
  final BoostController boost;
  final String version;
  final String buildNumber;
  final Future<bool> Function() privilegeProbe;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;

  static const double _railBreakpoint = 900;

  @override
  void initState() {
    super.initState();
    widget.metrics.start();
    widget.quarantine.load();
  }

  @override
  void dispose() {
    widget.metrics.stop();
    super.dispose();
  }

  Future<void> _showLog() async {
    final l10n = AppLocalizations.of(context);
    final lines = List<String>.of(log.recent).reversed.take(80).toList();
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.dashboardActivityLog),
        content: SizedBox(
          width: 640,
          child: lines.isEmpty
              ? Text(l10n.dashboardLogEmpty)
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final line in lines)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(line,
                              style: const TextStyle(
                                  fontFamily: 'monospace', fontSize: 12)),
                        ),
                    ],
                  ),
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.actionClose),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final destinations = <_Destination>[
      _Destination(
        icon: Icons.speed_outlined,
        selectedIcon: Icons.speed,
        label: l10n.navDashboard,
      ),
      _Destination(
        icon: Icons.cleaning_services_outlined,
        selectedIcon: Icons.cleaning_services,
        label: l10n.navCleaner,
      ),
      _Destination(
        icon: Icons.copy_all_outlined,
        selectedIcon: Icons.copy_all,
        label: l10n.navDuplicates,
      ),
      _Destination(
        icon: Icons.restore_outlined,
        selectedIcon: Icons.restore,
        label: l10n.navQuarantine,
      ),
      _Destination(
        icon: Icons.photo_library_outlined,
        selectedIcon: Icons.photo_library,
        label: l10n.navLibrary,
      ),
      _Destination(
        icon: Icons.apps_outlined,
        selectedIcon: Icons.apps,
        label: l10n.navApps,
      ),
      _Destination(
        icon: Icons.bolt_outlined,
        selectedIcon: Icons.bolt,
        label: l10n.navBoost,
      ),
      _Destination(
        icon: Icons.settings_outlined,
        selectedIcon: Icons.settings,
        label: l10n.navSettings,
      ),
    ];

    final pages = <Widget>[
      DashboardScreen(
        metrics: widget.metrics,
        cleaner: widget.cleaner,
        quarantine: widget.quarantine,
        onOpenCleaner: () => _select(1),
      ),
      CleanerScreen(controller: widget.cleaner),
      DuplicatesScreen(controller: widget.duplicates),
      QuarantineScreen(controller: widget.quarantine),
      LibraryScreen(
        controller: widget.library,
        onGrantAccess: widget.library.requestAccess,
        onOpenDuplicates: () => _select(2),
      ),
      UnusedAppsScreen(
        controller: widget.apps,
        onGrantUsageAccess: widget.apps.requestAccess,
      ),
      BoostScreen(controller: widget.boost),
      SettingsScreen(
        controller: widget.settings,
        quarantinePath: widget.quarantine.quarantine.root.path,
        version: widget.version,
        buildNumber: widget.buildNumber,
        onOpenLog: _showLog,
        privilegeProbe: widget.privilegeProbe,
      ),
    ];

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CyberBackground(
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final wide = constraints.maxWidth >= _railBreakpoint;
              final body = IndexedStack(index: _index, children: pages);
              if (wide) {
                return Row(
                  children: [
                    _Rail(
                      index: _index,
                      destinations: destinations,
                      onSelected: _select,
                    ),
                    VerticalDivider(
                      width: 1,
                      color: CyberTheme.of(Theme.of(context)).outline,
                    ),
                    Expanded(child: body),
                  ],
                );
              }
              return Column(
                children: [
                  Expanded(child: body),
                  NavigationBar(
                    height: 68,
                    selectedIndex: _index,
                    onDestinationSelected: _select,
                    destinations: [
                      for (final destination in destinations)
                        NavigationDestination(
                          icon: Icon(destination.icon),
                          selectedIcon: Icon(destination.selectedIcon),
                          label: destination.label,
                        ),
                    ],
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }
}

class _Destination {
  const _Destination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

class _Rail extends StatelessWidget {
  const _Rail({
    required this.index,
    required this.destinations,
    required this.onSelected,
  });

  final int index;
  final List<_Destination> destinations;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    final l10n = AppLocalizations.of(context);
    return SizedBox(
      width: 208,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 12),
            child: Row(
              children: [
                Icon(Icons.hexagon_outlined, color: palette.accent, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    l10n.appTitle,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.textPrimary,
                          letterSpacing: context.tightTracking,
                        ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: NavigationRail(
              backgroundColor: Colors.transparent,
              selectedIndex: index,
              onDestinationSelected: onSelected,
              labelType: NavigationRailLabelType.all,
              useIndicator: true,
              destinations: [
                for (final destination in destinations)
                  NavigationRailDestination(
                    icon: Icon(destination.icon),
                    selectedIcon: Icon(destination.selectedIcon),
                    label: Text(destination.label),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
