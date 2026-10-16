import 'package:flutter/foundation.dart';

import '../../core/util/logger.dart';
import '../../engine/platform/storage_gateway.dart';

/// What the library screen is doing right now.
enum LibraryPhase { idle, loading, done, empty, blind, failed }

/// The photo and file browser.
///
/// On Android the media lives in a content provider, so this controller asks
/// the platform what it holds instead of walking a directory the process cannot
/// even open. It deliberately does *not* cache between screens: the whole point
/// is that the answer reflects the phone right now, not what it looked like
/// when the app started.
class LibraryController extends ChangeNotifier {
  LibraryController({required StorageGateway gateway}) : _gateway = gateway;

  final StorageGateway _gateway;

  MediaKind _kind = MediaKind.photos;
  List<MediaItem> _items = const <MediaItem>[];
  LibraryPhase _phase = LibraryPhase.idle;
  bool _loading = false;

  /// Which library is on screen.
  MediaKind get kind => _kind;

  /// The files on screen, newest first.
  List<MediaItem> get items => _items;

  LibraryPhase get phase => _phase;

  bool get isLoading => _loading;

  /// True when the platform could not be asked at all — a missing permission or
  /// a provider that is not there. The screen must say so rather than show an
  /// empty gallery and let the user conclude they have no photos.
  bool get isBlind => _phase == LibraryPhase.blind;

  bool get isEmpty => _items.isEmpty;

  int get totalBytes =>
      _items.fold<int>(0, (int sum, MediaItem m) => sum + m.sizeBytes);

  /// Nothing has been asked yet, or a load is already running.
  bool get canLoad => !_loading;

  /// Switches library. Any list already on screen is dropped immediately: a
  /// stale photo grid under a "Videos" tab is worse than a brief empty state.
  void selectKind(MediaKind next) {
    if (next == _kind) return;
    _kind = next;
    _items = const <MediaItem>[];
    _phase = LibraryPhase.idle;
    notifyListeners();
  }

  /// Asks the platform for whatever grant is missing, then reloads.
  ///
  /// The request itself has to come from the host, so the button is wired to
  /// this and the screen calls it before re-reading the library.
  Future<void> requestAccess() async {
    await _gateway.requestAccess();
    await load();
  }

  Future<void> load() async {
    if (_loading) return;
    _loading = true;
    _phase = LibraryPhase.loading;
    _items = const <MediaItem>[];
    notifyListeners();

    try {
      final StorageCapabilities caps = await _gateway.capabilities();
      if (!caps.canReadAnything) {
        _phase = LibraryPhase.blind;
        _loading = false;
        notifyListeners();
        return;
      }

      final List<MediaItem> merged = <MediaItem>[];
      for (final MediaKind source in _kind.sources) {
        merged.addAll(await _gateway.media(kind: source));
      }

      merged.sort((MediaItem a, MediaItem b) {
        final int byDate = b.modified.compareTo(a.modified);
        return byDate != 0 ? byDate : a.name.compareTo(b.name);
      });

      _items = List<MediaItem>.unmodifiable(merged);
      _phase = merged.isEmpty ? LibraryPhase.empty : LibraryPhase.done;
    } catch (error) {
      log.error('library: load failed — $error');
      _items = const <MediaItem>[];
      _phase = LibraryPhase.failed;
    }

    _loading = false;
    notifyListeners();
  }
}
