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

  Two things worth weighing that were not known when this was written. Every
  change so far has merged without a review — not one merged pull request
  carries one — and consecutive audits of the contribution files each found
  problems in the pull requests that preceded them: the kind a second reader
  catches and an author does not, because the author checks what they meant
  rather than what they wrote. Against that, the repository now has an outside
  contributor, so a reviewer exists where none did.
- **Whether to take the published repository out of git entirely.** #12 stopped
  `gh-pages` accumulating — a publish now replaces it with one orphan commit
  instead of adding to it — but the branch still holds a published tree that
  every clone pays for, and each publish still writes ~60 MB of blobs that only
  GitHub's garbage collection removes. The alternative is Pages' `workflow` build type:
  `actions/deploy-pages` serves an uploaded artifact, nothing enters git, and
  this repository stays at ~1 MB. The cost is that `publish.sh` is incremental
  — it merges into the previous tree and prunes it — so the state it needs would
  have to come from somewhere other than a branch: the live site, enumerated
  from `repodata/*-primary.xml.gz`, or a Release asset holding a tarball. A
  branch is also a backup you can check out, which neither of those is.

  [#15](https://github.com/xymon-monitoring/xymon-rpm/issues/15) settled the
  half of this it was watching, and settled it against building C: GitHub's
  collection kept up easily, taking the repository from 2.15 GiB to 41 MB
  within hours of the first orphan push rather than the week or two expected.
  Unbounded growth is not a reason to do this.

  The other two reasons are untouched by that, and this entry did not name
  them. A contributor still clones the published tree — roughly 460 MB once the
  retention window refills, at ten upstream builds of about 60 MB each — and
  that cost is what couples retention to contribution: raising
  `XYMON_SNAPSHOT_KEEP` buys rollback depth by making every clone larger.
  Taking the tree out of git decouples them. So this is no
  longer a fix for a growth problem, it is a convenience — worth doing
  deliberately rather than soon, and worth doing as a change that touches
  nothing else, since the publishing path is the only code here whose failure a
  user meets.
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
