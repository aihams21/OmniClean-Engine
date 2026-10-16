# Contributing to OmniClean Engine

Thanks for looking at this project. OmniClean deletes files, so the bar for a
change is a little higher than usual: **it must not be able to delete something
it should not.**

Read [SECURITY.md](SECURITY.md) before you touch anything under
`lib/core/safety/` — it is the only part of the codebase where a small mistake
is unrecoverable.

---

## Getting set up

```bash
git clone https://github.com/aihams21/OmniClean-Engine.git
cd OmniClean-Engine

# Flutter 3.50.0 or newer (Dart 3.14+)
flutter --version

flutter pub get
flutter test          # 248 tests, ~30 s
flutter analyze       # must stay at zero errors and zero warnings
```

Desktop builds additionally need the GTK toolchain:

```bash
sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
flutter run -d linux
```

## Ground rules

1. **Tests first.** Every behaviour change starts as a failing test. Red,
   green, refactor. A bug fix without a regression test will not be merged,
   because the bug will come back.
2. **One hypothesis per test.** If a test fails, fix the thing it is actually
   asserting. Do not widen an assertion until it passes — that is how a real
   bug hides.
3. **Never claim it works until you have run it.** Paste the command *and* the
   output. "Should work" is not evidence.
4. **No comments that say what the code says.** Comment the *why* — especially
   the safety reasoning, which is not obvious from the code alone.
5. **Match the surrounding style.** `dart format` and `flutter analyze
   --no-fatal-infos` must both be clean before you open a pull request.

## Where things live

```
lib/core/safety/     deny-list, quarantine, SafeDelete — read SECURITY.md first
lib/core/util/       byte formatting, the in-memory ring-buffer logger
lib/engine/duplicates/  SHA-256 hasher + the 3-pass duplicate finder
lib/engine/cleaners/     directory sweeper + per-platform target sets
lib/engine/metrics/      /proc + PowerShell parsing, the sampling service
lib/engine/shell.dart    privilege escalation and subprocess execution
lib/ui/                 theme, l10n (ARB), widgets, controllers, screens
lib/bootstrap.dart       wires everything together at startup
test/                   mirrors lib/ 1:1
tool/packaging/          .deb / AppImage / tar.gz builders
tool/build_walkthrough_gifs.py   regenerates docs/walkthrough/*.gif
```

## Adding a cleaning module

1. Declare a `CleanTarget` with an `id`, `titleKey`, `descriptionKey`,
   `category`, `risk`, `requiresPrivilege` and, above all, `roots`. A target
   without roots is a bug — `CleanTargetSet` does not stop you, but a reviewer
   will.
2. Pick `minAge` honestly. "0" means you are deleting things an app may still
   hold open.
3. Choose `risk` from what the module really does, not from how convenient it
   would be to default to `safe`.
4. Add the two ARB keys (`targetXxxTitle` / `targetXxxDescription`) to **both**
   `app_en.arb` and `app_ar.arb`, then run `flutter gen-l10n`. ARB resource
   names must be valid camelCase Dart identifiers.
5. Write a test that asserts the roots, the risk and the privilege requirement.

## Adding a string

Never hard-code user-visible text. Add the key to `lib/ui/l10n/arb/app_en.arb`
**and** `app_ar.arb`, run `flutter gen-l10n`, and use it via
`AppLocalizations.of(context)`.

Arabic-specific rules learned the hard way:

- **Never apply positive `letterSpacing` to Arabic.** It stretches the joining
  strokes and breaks shaping. Use `context.labelTracking` / `context.tightTracking`
  from `app_theme.dart`, which return 0 for non-Latin scripts.
- Any `TextStyle` you build outside `_textTheme` must carry
  `AppTheme.fontFallbacks`, or Arabic renders as tofu boxes.
- The app shows *unavailable*, never a fabricated `0 %`.

## Pull requests

- Branch from `main`, one logical change per branch.
- The `analyze`, `test` and `security` CI jobs must pass. The `security` job
  fails the build if a keystore is ever tracked — that is not negotiable.
- Describe what changed, what you tested, and how you know nothing important
  can be deleted by it.

## Reporting bugs

Open an issue with the platform, the version (`Settings → About`), the module,
and what you expected versus what happened. If a file disappeared that should
not have: **go to Quarantine and restore it**, then tell us — the manifest
records exactly which module claimed the path, which is the single most useful
piece of evidence we can get.
