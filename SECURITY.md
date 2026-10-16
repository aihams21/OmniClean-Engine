# Security Policy

OmniClean Engine deletes files. A cleaner that deletes files has one
requirement that outranks every feature: **it must be wrong safely.**

---

## 1. The safety model in one paragraph

OmniClean Engine **never unlinks data**. Every file or directory it decides to
remove is *moved* into a per-user quarantine directory and recorded in a JSON
manifest. Recovery is therefore a single click on **Quarantine → Restore**, for
the entire retention window (7 days by default). Permanent deletion only ever
happens when the user explicitly presses *Purge*, or when the retention window
expires.

```
scan → gate → move to quarantine → (restore anytime) → purge when the user says so
```

## 2. Three independent gates

Every single path — not every scan, **every path** — is re-validated by
`SafeDelete` before it is touched. A bug in a scanner therefore cannot turn into
a deletion outside the declared roots.

| Gate | Class | What it refuses |
|---|---|---|
| 1 | `ProtectedPaths` | Credentials (`.ssh`, `.gnupg`, `.aws`, `.kube`), configuration (`.config`), version-control metadata (`.git`, `.svn`), databases and key material by extension (`.db`, `.sqlite`, `.key`, `.pem`, `.wallet`, `.crt`, …), every system tree (`/bin`, `/boot`, `/etc`, `/lib`, `/proc`, `/sys`, `/usr`, …), `C:\Windows` except a short allow-list of temp/log paths, `Program Files`, `$Recycle.Bin`, `System Volume Information`. |
| 2 | `allowedRoots` | Anything outside the roots the module itself declared. A scanner that walks the wrong directory is a bug we want to hear about loudly, not clean up silently. |
| 3 | `type / mtime` | Symlinks (never followed — this is what stops `~/.cache/x → /` from wiping the disk), missing paths, and anything touched more recently than `minAge` (default 24 h), because a live process is probably still using it. |

A refusal is **never fatal**. It is counted and reported as *held back*, so one
protected file cannot strand an entire cleanup run.

## 3. Honest numbers

A cleaner that reports "1.2 GB reclaimable" when it cannot deliver it is worse
than no cleaner at all. This project therefore separates:

- **Reclaimable now** — what passed every gate and can be moved right now.
- **Held back** — what exists but is held by the age gate or a protection rule.

The same rule applies to the RAM gauge: it reports kernel-available memory
(`MemAvailable`), never a fabricated percentage, and every gauge shows
*unavailable* rather than `0 %` when the kernel gives it nothing to read.

## 4. Privileges

- Linux modules that need root declare `requiresPrivilege` and are visibly
  marked. Escalation goes through `pkexec` or non-interactive `sudo`; if neither
  is available the module reports that it could not run instead of failing
  silently or faking a result.
- Windows modules never need elevation for the cleanable temp/log paths.
- On Android, `/data/data` and `/data/user/0` are only offered when a root
  helper is actually present. The unprivileged path uses scoped storage only.

## 5. Reporting a vulnerability

Please **do not open a public issue** for a security problem.

Send a private report through GitHub's *Security → Report a vulnerability* tab on
<https://github.com/aihams21/OmniClean-Engine>, or email the maintainer
directly. Include:

- the platform and OmniClean version (`Settings → About`),
- the module and target involved,
- the exact path, and
- why you believe the deny-list let it through.

We aim to acknowledge within 72 hours and to ship a fix or a documented
mitigation within 14 days.

### What counts as a vulnerability

- Any path that `ProtectedPaths` permits but should not (e.g. a symlink,
  a case-folding bypass on Windows, a path-traversal escape).
- Any route that unlinks data without a quarantine receipt.
- Any escalation to root that is not explicitly requested by the user.

### What is not a vulnerability

- Losing data that was still inside the retention window — press Restore.
- A module reporting less reclaimable space than another tool — that is a
  correctness question, not a security one. Please open a normal issue.

## 6. Secrets in this repository

No signing key is committed, ever. `android/key.properties`, `*.jks` and
`*.keystore` are git-ignored, and the `security` job in CI **fails the build**
if any of them is ever tracked. Release signing happens on the CI runner using
GitHub Actions secrets.

## 7. Data collection

There is none. OmniClean Engine has no telemetry, no analytics, no crash
reporting and no network code in the shipped application. The activity log you
see on the dashboard lives in memory for the lifetime of the process and is
never written to disk or transmitted.
