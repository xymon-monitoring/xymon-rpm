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

  **What "upstream's required review" is, exactly.**
  `xymon-monitoring/xymon` carries an active `protected-branches` ruleset on
  `main`, `devel` and `release/*`: one approving review, approval of the last
  push, stale reviews dismissed when a branch moves, review threads resolved
  before merge. The default there is that a change is reviewed. The
  `maintainers` team — nine people — carries `bypass_mode: always`, which is
  the whole ruleset and not the review alone: a maintainer can also push
  straight to `main`, or force it. Of the twenty most recently merged pull
  requests there, eight carry no review.

  So adopting it here means adopting *reviewed by default, bypassable by
  whoever maintains the repository*. With one maintainer pushing, that is the
  state this repository is in already, minus the written default. Whether the
  written default earns its keep on its own — as something a first outside
  contributor reads, and as the thing a bypass is measured against — is the
  question, rather than whether it would stop anything today.

  **The disclosure rule waits on this.** CONTRIBUTING *Pull requests* asks an
  author to say in the pull request if they merged their own — a social rule
  standing in for the protection that does not exist. An audit of the twenty-nine
  merged on 15 September found it followed in 2 of the 27 it binds, so it is not
  standing in for much. Required review would retire it rather than mend it:
  there would be no self-merge left to disclose. So how it is rewritten follows
  from this decision and should not be patched ahead of it.
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
- **Whether to put the packages in Fedora, and through it EPEL.** RHEL itself is
  not a community path — Red Hat decides what it ships and supports. "Official
  for RHEL" means EPEL in practice, EPEL is built from Fedora, so the route is
  Fedora first and EPEL branches after: a review ticket, a sponsor for a first
  package, then dist-git and Koji. Xymon is in neither today (checked against
  Fedora's project API, where `nagios` answers and `xymon` and `hobbit` do not),
  so it is a new submission rather than taking one over.

  What it buys is what a user notices: no third-party repository to add, no
  `.repo` file, no key to trust. That is also the cost. This packaging iterates
  — versions derived from two git trees, a publish per commit, no hand-written
  changelog — and a distribution package is the opposite regime. The question
  under the question is whether one spec serves both or a submission is its own.

  The spec is closer than third-party specs usually are: SPDX licence, no
  obsolete tags, no patches, scriptlet `Requires(pre/post)`, sysusers with an
  EL8 fallback, every `%config` `noreplace`, and `Provides: %{name}-static` in
  the form the guidelines ask for. The one hard blocker — a build that ignored
  the distribution's flags — closed when `%build` took `%{optflags}`.

  Four things remain, and only one is a decision:
  - `%changelog` is empty because the version is derived; Fedora wants entries.
    One written at each release satisfies it without touching the model.
  - `Conflicts: xymon-client` between subpackages is what a review pushes back
    on hardest, and it is
    [deployment-strategies.md](deployment-strategies.md) rather than an
    oversight. Changing it changes the product, not the packaging. **This is
    the decision.**
  - `%pretrans` in lua is the layout migration, and it ends when no supported
    upgrade starts from the old layout — after the first release.
  - The SELinux policy is `%bcond_with`, off, and its target is an unpublished
    canary. Nothing to decide until it ships.
- **The eventual move upstream.** [upstream.md](upstream.md) intends to move
  the spec and workflow into `xymon-monitoring/xymon` once stable, leaving this
  repo as the publish target. Part of that is deciding the fate of upstream's
  own stale `rpm/` (2014, SysV) and `debian/` (2019) packagings.

- **The client's drop-in directories, with or without xymon#411.**
  `clientlaunch.cfg` and `xymonclient.cfg` each end in `optional directory
  @XYMONHOME@/etc/<name>`, and the packages ship neither `clientlaunch.d` nor
  `xymonclient.d`. `optional` means nothing fails: a drop-in file is silently
  never read, which is how it surfaced as xymon#522 rather than as a crash.

  It is not theoretical. xymon#522 asks for `clientlaunch.d` to be created and
  packaged, from someone who met the gap on an installed system — and it
  patches `rpm/xymon.spec` inside `xymon-monitoring/xymon`, the unmaintained
  2014 spec that [CONTRIBUTING](../CONTRIBUTING.md) *Which repository* says is
  reviewed by nobody and shipped to nobody. So the report is real, the fix sits
  where no user installs from, and this packaging still has the gap it
  describes — the reason that rule exists, in one example. It covers
  `clientlaunch.d` only, not `xymonclient.d`.

  **The packaging half is done.** `%files` named `/etc/xymon-client`'s
  contents one by one where the server half globs, which is why upstream's nine
  server drop-in directories have always been packaged and the client's two
  would not be. It globs now, so whatever upstream's `client/etc` holds is
  packaged — which is right whether or not xymon#411 ever lands, and is why it
  did not have to be timed against it.

  What is left is one trade: whether to ship the directories *before*
  xymon#411 merges:

  - **Compensate now** — `install -d` the two in `%install`, naming xymon#411
    in the comment beside it and in [upstream.md](upstream.md). Users get a
    working extension point at the next snapshot, at the price of an interim
    override to delete later.
  - **Wait** — the gap stays until xymon#411 lands, and then only the glob is
    needed. Cheaper, and it leaves users with a documented feature that does
    nothing in the meantime.

  The glob is what makes *Wait* safe. `check-files` lists `-type f -o -type l`,
  so an unpackaged *directory* is never reported: with the old list, xymon#411
  would have merged, the build would have stayed green, and the package would
  still have shipped without them, with nothing saying so.

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
