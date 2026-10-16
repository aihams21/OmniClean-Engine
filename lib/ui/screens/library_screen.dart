import 'package:flutter/material.dart';

import '../../core/util/byte_fmt.dart';
import '../../engine/platform/storage_gateway.dart';
import '../controllers/library_controller.dart';
import '../l10n/generated/app_localizations.dart';
import '../theme/app_theme.dart';

/// The photos and files the device actually holds.
///
/// Nothing here asks for a folder: the platform already knows its own media
/// library, so the only question left is which shelf of it to look at.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({
    required this.controller,
    this.onGrantAccess,
    this.onOpenDuplicates,
    super.key,
  });

  final LibraryController controller;

  /// Invoked by the permission button. Omitted when the host cannot request
  /// grants, in which case the button simply says why access is missing.
  final VoidCallback? onGrantAccess;

  final VoidCallback? onOpenDuplicates;

  static const List<MediaKind> _kinds = <MediaKind>[
    MediaKind.photos,
    MediaKind.videos,
    MediaKind.audio,
    MediaKind.documents,
    MediaKind.downloads,
    MediaKind.allFiles,
  ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final palette = CyberTheme.of(Theme.of(context));
    final arabic = Localizations.localeOf(context).languageCode == 'ar';
    String bytes(int value) =>
        formatBytes(value, unitSystem: arabic ? 'ar' : 'en');

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.libraryTitle,
                          style: Theme.of(context).textTheme.headlineSmall),
                      Text(
                        l10n.librarySubtitle,
                        style: Theme.of(context)
                            .textTheme
                            .bodyMedium
                            ?.copyWith(color: palette.textMuted),
                      ),
                    ],
                  ),
                ),
                if (controller.canLoad)
                  FilledButton.icon(
                    onPressed: controller.load,
                    icon: controller.isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh),
                    label: Text(
                      controller.isLoading
                          ? l10n.libraryReloading
                          : l10n.libraryLoad,
                    ),
                  ),
              ],
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                for (final MediaKind kind in _kinds)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_label(l10n, kind)),
                      selected: controller.kind == kind,
                      onSelected:
                          controller.isLoading ? null : (_) => _openShelf(kind),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          Expanded(child: _body(context, l10n, palette, bytes)),
        ],
      ),
    );
  }

  /// Switching shelf fetches that shelf.
  ///
  /// Clearing the list and leaving the user to press Load again would answer
  /// "you have no videos" when the truth is "nobody has asked yet".
  void _openShelf(MediaKind kind) {
    controller.selectKind(kind);
    controller.load();
  }

  static String _label(AppLocalizations l10n, MediaKind kind) {
    switch (kind) {
      case MediaKind.photos:
        return l10n.libraryKindPhotos;
      case MediaKind.videos:
        return l10n.libraryKindVideos;
      case MediaKind.audio:
        return l10n.libraryKindAudio;
      case MediaKind.documents:
        return l10n.libraryKindDocuments;
      case MediaKind.downloads:
        return l10n.libraryKindDownloads;
      case MediaKind.allFiles:
        return l10n.libraryKindAllFiles;
    }
  }

  Widget _body(
    BuildContext context,
    AppLocalizations l10n,
    CyberPalette palette,
    String Function(int) bytes,
  ) {
    if (controller.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (controller.isBlind) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 40, color: palette.warning),
              const SizedBox(height: 12),
              Text(
                l10n.libraryBlind,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: palette.warning),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.libraryBlindHint,
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: palette.textMuted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onGrantAccess,
                icon: const Icon(Icons.lock_open),
                label: Text(l10n.libraryGrant),
              ),
            ],
          ),
        ),
      );
    }
    if (controller.phase == LibraryPhase.failed) {
      return _Centered(
        text: l10n.libraryFailed,
        color: palette.danger,
      );
    }
    if (controller.phase == LibraryPhase.idle) {
      // The app has not looked yet. Saying "nothing here" before it has would
      // be a lie about the user's own files.
      return _Centered(text: l10n.librarySubtitle, color: palette.textMuted);
    }
    if (controller.isEmpty) {
      return _Centered(text: l10n.libraryEmpty, color: palette.textMuted);
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: Row(
            children: [
              Text(
                l10n.libraryCount(
                    controller.items.length, bytes(controller.totalBytes)),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: palette.accent),
              ),
              const Spacer(),
              if (onOpenDuplicates != null)
                TextButton.icon(
                  onPressed: onOpenDuplicates,
                  icon: const Icon(Icons.content_copy, size: 18),
                  label: Text(l10n.libraryUseDuplicates),
                ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            itemCount: controller.items.length,
            separatorBuilder: (BuildContext _, int __) =>
                const Divider(height: 1),
            itemBuilder: (context, index) {
              final MediaItem item = controller.items[index];
              return _Row(item: item, sizeText: bytes(item.sizeBytes));
            },
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item, required this.sizeText});

  final MediaItem item;
  final String sizeText;

  @override
  Widget build(BuildContext context) {
    final palette = CyberTheme.of(Theme.of(context));
    final bool hasPixels = item.width > 0 && item.height > 0;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(
            item.isVideo
                ? Icons.movie_outlined
                : item.isImage
                    ? Icons.photo_outlined
                    : Icons.insert_drive_file_outlined,
            color: palette.accent,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  item.path,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: palette.textMuted, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
          if (hasPixels)
            Padding(
              padding: const EdgeInsets.only(left: 12),
              child: Text(
                AppLocalizations.of(context)
                    .libraryResolution(item.width, item.height),
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: palette.textMuted),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              sizeText,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(color: palette.accent),
            ),
          ),
        ],
      ),
    );
  }
}

class _Centered extends StatelessWidget {
  const _Centered({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: color),
        ),
      );
}
