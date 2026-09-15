# Roadmap

The **live trackers already exist and are checked in CI** — don't duplicate
them here:

- upstream fixes that let the spec drop a workaround → [upstream.md](upstream.md)
  *Gaps sent back upstream* (a PR table, verified nightly by `docs.sh`)
- runtime shortfalls waiting on upstream → README *Known gaps*

This file is for what those don't cover: **decisions to make, and packaging
work with no upstream PR behind it.** Keep it short; move anything actionable
to a GitHub issue.

## Decisions

- **Review policy for this repo.** `main` is unprotected, so a change can merge
  with no second reviewer — which is why packaging *can* iterate fast, but also
  lets self-authored work land unreviewed. Options: adopt upstream's required
  review; keep it open; or a middle path — protect `main` but require review
  only for `rpm/` and `build/`, letting docs-only through (matches the
  "commit documentation separately" split). Decide deliberately.
- **Whether to take the published repository out of git entirely.** #12 stopped
  `gh-pages` accumulating — a publish now replaces it with one orphan commit
  instead of adding to it — but the branch still holds ~300 MB that every clone
  pays for, and each publish still writes ~60 MB of blobs that only GitHub's
  garbage collection removes. The alternative is Pages' `workflow` build type:
  `actions/deploy-pages` serves an uploaded artifact, nothing enters git, and
  this repository stays at ~1 MB. The cost is that `publish.sh` is incremental
  — it merges into the previous tree and prunes it — so the state it needs would
  have to come from somewhere other than a branch: the live site, enumerated
  from `repodata/*-primary.xml.gz`, or a Release asset holding a tarball. A
  branch is also a backup you can check out, which neither of those is. What
  decides this is already measuring itself: [#15](https://github.com/xymon-monitoring/xymon-rpm/issues/15)
  watches whether the repository size falls back to the published tree. If
  GitHub's collection keeps up, this is not worth building; if the size climbs,
  #12 only moved the growth out of sight of clones. Decide when #15 closes.
- **The eventual move upstream.** [upstream.md](upstream.md) intends to move
  the spec and workflow into `xymon-monitoring/xymon` once stable, leaving this
  repo as the publish target. Part of that is deciding the fate of upstream's
  own stale `rpm/` (2014, SysV) and `debian/` (2019) packagings.

## Packaging work (no upstream PR)

- **Reconcile the SELinux `.te` with `%post`.** The modules still reference
  `/var/cache/xymon`, which this layout does not use; the real labeling is in
  `%post` ([selinux.md](selinux.md)).
- **Validate on an enforcing host.** CI compiles the policy but never runs
  enforcing — needs a real RHEL/Oracle box ([selinux.md](selinux.md)).
- **Validate on genuine RHEL and OracleLinux.** CI builds on AlmaLinux (a RHEL
  rebuild), which cannot surface a symbol RHEL lacks; real RHEL/OL testing is a
  standing gap. Recruit downstream testers.
- **Add a `CONTRIBUTING.md`.** No front door for a new packager: how to install
  the snapshot and report, where to file (rpm issues vs source issues), what
  needs real-host validation, and the review rule.
- **Cut the first release.** The stable channel is empty until the first
  `rel-*` tag; cut it when 4.3.31 releases upstream.
- **A stable-release upgrade path.** A server upgrade currently needs a manual
  `dnf swap` — the package conflict makes `dnf upgrade` stop otherwise. A stable
  release needs a `%triggerun` migration or a transitional package
  ([admin-guide.md](admin-guide.md) *Migrating from the old layout*).
- **Watch the signing key expiry** ([signing.md](signing.md) *Renewing before
  expiry*).

## Tracked elsewhere (pointers, not tasks)

- Enabling distribution hardening — [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163)
  (RPM) and the Debian `CPPFLAGS` gap [xymon#444](https://github.com/xymon-monitoring/xymon/issues/444)
- `/run/xymon` + `SIGHUP` relay — the `#219 → #172` stack (README *Known gaps*)
- Consuming a merged upstream feature — one spec PR each, e.g.
  [xymon-rpm#4](https://github.com/xymon-monitoring/xymon-rpm/pull/4) once
  [xymon#414](https://github.com/xymon-monitoring/xymon/pull/414) lands
