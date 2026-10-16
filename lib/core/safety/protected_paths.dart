import '../util/logger.dart';

/// The hard deny-list of OmniClean Engine.
///
/// Every module asks [isProtected] before touching a single byte. It is
/// intentionally paranoid: a false positive only means "we did not clean
/// this", while a false negative can destroy someone's life. Therefore the
/// rules are *structural* (whole subtrees) rather than per-file heuristics,
/// and they are matched with **segment equality**, never `contains`, so
/// `/tmp/cache/whatever` stays cleanable but `/home/you/.ssh/whatever`
/// never does.
class ProtectedPaths {
  const ProtectedPaths._();

  /// Top-level POSIX trees that must never be modified, at any depth.
  static const Set<String> _protectedRoots = {
    'bin',
    'boot',
    'dev',
    'etc',
    'lib',
    'lib32',
    'lib64',
    'libx32',
    'proc',
    'run',
    'sbin',
    'sys',
    'usr',
  };

  /// `/var` is largely a cleaner target (`/var/cache/apt/archives`), so only
  /// the state-bearing parts are locked.
  static const Set<String> _protectedVarDirs = {
    'lib',
    'spool',
    'backups',
    'mail',
  };

  /// Directory *names* that hold credentials, configuration or history.
  /// Matched as exact path segments.
  static const Set<String> _sensitiveDirs = {
    '.ssh', '.gnupg', '.gpg', '.pgp', '.password-store', 'keyrings',
    'credentials', '.config', '.aws', '.azure', '.kube', '.docker', '.gem',
    '.npm', '.cargo', '.local/state',
    // Version-control metadata: deleting a `.git` directory destroys work
    // history that exists nowhere else.
    '.git', '.svn', '.hg', '.bzr',
  };

  /// Profile directories that are *state*, not cache.
  ///
  /// These are matched only when the path contains no cache segment at all:
  /// `~/.config/mozilla` is a live Firefox profile (bookmarks, logins,
  /// extensions) and must survive, while `~/.cache/mozilla/.../diskCache` is
  /// exactly the junk we are after.
  static const Set<String> _sensitiveDirsOutsideCache = {
    '.mozilla',
    '.thunderbird',
    'mozilla',
    'thunderbird',
    'keychains',
  };

  /// Segment names that start a disposable cache subtree.
  static const Set<String> _cacheSegments = {
    '.cache',
    'cache',
    'caches',
    'code cache',
    'gpucache',
    'cache2',
  };

  /// File names that hold credentials, configuration or shell history.
  static const Set<String> _sensitiveFiles = {
    '.bashrc',
    '.bash_profile',
    '.bash_login',
    '.bash_logout',
    '.bash_history',
    '.zshrc',
    '.zprofile',
    '.zshenv',
    '.zlogin',
    '.profile',
    '.gitconfig',
    '.netrc',
    '_netrc',
    '.npmrc',
    '.pypirc',
    '.clinerules',
    '.agentrc',
    '.env',
    '.envrc',
    'authorized_keys',
    'known_hosts',
    'id_rsa',
    'id_dsa',
    'id_ecdsa',
    'id_ed25519',
    'crontab',
    'master.passwd',
    'shadow',
    'passwd',
    'group',
  };

  /// Extensions carrying databases, dumps or key material.
  ///
  /// `.db` is here on purpose: SQLite databases are the single most common
  /// thing a naive "cache cleaner" destroys, and the mission of this app is
  /// to never be that app.
  static const List<String> _protectedExtensions = [
    '.db',
    '.db3',
    '.db-wal',
    '.db-shm',
    '.sqlite',
    '.sqlite-wal',
    '.sqlite-shm',
    '.sqlite2',
    '.sqlite3',
    '.sql',
    '.dump',
    '.rdb',
    '.aof',
    '.ibd',
    '.frm',
    '.myd',
    '.mdb',
    '.key',
    '.keys',
    '.pem',
    '.p12',
    '.pfx',
    '.jks',
    '.keystore',
    '.asc',
    '.gpg',
    '.pgp',
    '.kdbx',
    '.kdb',
    '.ppk',
    '.keypair',
    '.wallet',
    '.ovpn',
    '.crt',
  ];

  /// Windows trees that are locked outright.
  static const Set<String> _protectedWindowsRoots = {
    'windows.old',
    'program files',
    'program files (x86)',
    'recovery',
    r'$recycle.bin',
    'system volume information',
    'perfmon logs',
  };

  /// Explicitly cleanable sub-paths inside `C:\Windows`. Everything else in
  /// that tree stays protected.
  static const List<String> _windowsCleanable = [
    '/windows/temp',
    '/windows/logs',
    '/windows/minidump',
    '/windows/livekernelreports',
    '/windows/panther',
    '/windows/system32/logfiles',
    '/windows/system32/winevt/logfiles',
    '/windows/inf/pending',
    '/windows/softwaredistribution/download',
    '/windows/softwaredistribution/deliveryoptimization',
  ];

  static final RegExp _drive = RegExp(r'^[a-z]:$');

  /// Normalises separators, collapses repeated slashes and strips a trailing
  /// slash, so Windows and POSIX paths share one comparison form.
  static String normalize(String path) {
    var p = path.replaceAll('\\', '/').trim();
    while (p.contains('//')) {
      p = p.replaceAll('//', '/');
    }
    if (p.length > 1 && p.endsWith('/')) {
      p = p.substring(0, p.length - 1);
    }
    return p;
  }

  /// True when [rawPath] must never be quarantined, trashed or pruned.
  static bool isProtected(String rawPath) {
    final path = normalize(rawPath);
    if (path.isEmpty || path == '/' || path == '.') return true;

    final segs = path
        .split('/')
        .where((s) => s.isNotEmpty && s != '.')
        .toList(growable: false);
    if (segs.isEmpty) return true;

    final isWindows = _drive.hasMatch(segs.first.toLowerCase());
    final rest = segs.sublist(isWindows ? 1 : 0);

    // A bare drive root (`C:/`) is the Windows equivalent of `/`.
    if (isWindows && rest.isEmpty) return true;

    if (isWindows) {
      final lower = path.toLowerCase();
      final first = rest.first.toLowerCase();
      final underCleanable = _windowsCleanable.any(lower.startsWith);
      if (!underCleanable) {
        if (first == 'windows') return true;
        if (_protectedWindowsRoots.contains(first)) return true;
      }
      // `C:\Users` and `C:\Users\<name>` (the home root) are locked; anything
      // deeper is judged by the sensitive-name rules below.
      if (first == 'users' && rest.length <= 2) return true;
    } else {
      final first = rest.first;
      if (_protectedRoots.contains(first)) return true;
      if (first == 'root') return true;
      if (first == 'home' && rest.length <= 2) return true;
      if (first == 'var' &&
          rest.length >= 2 &&
          _protectedVarDirs.contains(rest[1])) {
        return true;
      }
    }

    // Sensitive directories, judged by exact segment only.
    //
    // A profile directory such as `Mozilla` or `thunderbird` is only stateful
    // while *no* cache segment appears anywhere in the path: once a `cache`
    // segment is present we are unambiguously inside a disposable subtree
    // (Firefox on Windows keeps its profile in `AppData\Local\Mozilla` while
    // its actual cache lives in `...\Profiles\<id>\cache2`).
    final start = isWindows ? 1 : 0;
    final hasCacheSegment =
        segs.skip(start).any((s) => _cacheSegments.contains(s.toLowerCase()));
    for (var i = start; i < segs.length; i++) {
      final low = segs[i].toLowerCase();
      if (_sensitiveDirs.contains(low)) return true;
      if (!hasCacheSegment && _sensitiveDirsOutsideCache.contains(low)) {
        return true;
      }
    }

    final last = segs.last.toLowerCase();
    if (_sensitiveFiles.contains(last)) return true;

    for (final ext in _protectedExtensions) {
      if (last.endsWith(ext)) return true;
    }

    log.fine('protect: allow $path');
    return false;
  }

  /// True when [child] is [root] itself or lives underneath it, comparing
  /// whole segments so `/home/bo/.cache` never matches `/home/bob`.
  static bool isInside(String child, String root) {
    final c = normalize(child).toLowerCase();
    final r = normalize(root).toLowerCase();
    if (c == r) return true;
    final prefix = r.endsWith('/') ? r : '$r/';
    return c.startsWith(prefix);
  }

  /// Human-readable reason used by the UI when something is skipped.
  static String explain(String rawPath) {
    final path = normalize(rawPath);
    final segs = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segs.isEmpty) return 'filesystem root';
    final last = segs.last.toLowerCase();
    for (final ext in _protectedExtensions) {
      if (last.endsWith(ext)) return 'protected data file (*$ext)';
    }
    if (_sensitiveFiles.contains(last))
      return 'configuration or credential file';
    for (final s in segs) {
      final low = s.toLowerCase();
      if (_sensitiveDirs.contains(low))
        return 'credentials / configuration directory';
    }
    return 'system path';
  }
}
