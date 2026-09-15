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
- **The published tree, and where it lives.** *Decided.* It is in
  `xymon-monitoring/xymon-rpm-archive`, reaches users as a Pages artifact the
  publish job uploads, and is no longer a branch of this repository.
  [build-pipeline.md](build-pipeline.md) *Serving the tree from an artifact*
  and *The archive* have the mechanism.

  Three ways were open, and the reasoning is what dates rather than the
  outcome. Keeping `gh-pages` cost about four seconds of a publish and nothing
  on GitHub, but every clone of this repository fetched the rpms with it —
  roughly 460 MB at a full retention window. Deleting it outright made the
  clone cheap and needed a new state store written on the publishing path,
  giving up a copy of the published tree that a person can check out and
  restore. Moving it kept both, at the price of a credential, since
  `github.token` reaches only the repository running the workflow.

  What settled it was that the first two traded one property for the other and
  the third did not. [#15](https://github.com/xymon-monitoring/xymon-rpm/issues/15)
  had already removed the reason usually given for this — unbounded growth — by
  showing GitHub's collection take the repository from 2.15 GiB to 41 MB in
  hours.

  `gh-pages` is frozen rather than deleted: it holds the tree as it stood when
  the archive took over. Deleting it is the step that actually makes a clone of
  this repository cheap, and it waits on a few publishes going to the archive
  first — [#37](https://github.com/xymon-monitoring/xymon-rpm/issues/37) has
  the check to run and the command.
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

- Enabling distribution hardening — done for RPM with
  [xymon#163](https://github.com/xymon-monitoring/xymon/pull/163); the Debian
  `CPPFLAGS` gap remains,
  [xymon#444](https://github.com/xymon-monitoring/xymon/issues/444)
- `/run/xymon` + `SIGHUP` relay — the `#219 → #172` stack (README *Known gaps*)
- Consuming a merged upstream feature — one spec PR each, e.g.
  [xymon-rpm#4](https://github.com/xymon-monitoring/xymon-rpm/pull/4) once
  [xymon#414](https://github.com/xymon-monitoring/xymon/pull/414) lands
