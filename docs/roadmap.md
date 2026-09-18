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

- **The client's drop-in directories.** *Decided:* the spec creates them, as
  an interim override xymon#411 will delete. `clientlaunch.cfg` and
  `xymonclient.cfg` each end in `optional directory @XYMONHOME@/etc/<name>`,
  and nothing created either. `optional` means nothing fails: a drop-in file is
  silently never read, which is how it surfaced as xymon#522 rather than as a
  crash.

  What decided it was the cost of waiting, which is not what it looked like.
  The directories are empty and stay empty, so *Wait* read as leaving a
  documented feature doing nothing. It is worse than that: with no directory,
  the only way to add a client task is to edit `clientlaunch.cfg`, which ships
  `%config(noreplace)`. An edited copy stops following upstream: rpm keeps it
  and, on the day the shipped file changes, leaves the new one beside it as a
  `.rpmnew` to merge by hand. Not every snapshot — only when that file moves,
  which is rare — but from the first edit onward the host is on its own copy
  and no upgrade reaches it. With the directory, a customisation is a file of
  the admin's own and the shipped config keeps upgrading.

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

  The glob is what makes the override cheap to remove. `check-files` lists
  `-type f -o -type l`, so an unpackaged *directory* is never reported: with the
  old list, xymon#411 would have merged, the build would have stayed green, and
  the package would still have shipped without them, with nothing saying so.
  Now the `install -d` goes and the glob keeps packaging whatever upstream
  makes.

  **Three sentences here stop being true when
  [#66](https://github.com/xymon-monitoring/xymon-rpm/pull/66) lands**, and
  should change with it or straight after. That pull request packages
  `clientlaunch.d` with the client alone: a server reads its task list from
  `tasks.cfg` and never opens `clientlaunch.cfg`, so a drop-in beside the
  server's copy would be silently unused. What each becomes:

  - *Decided: the spec creates them, as an interim override xymon#411 will
    delete* — only the `install -d` is interim. The `%exclude` is permanent,
    because which of two packages owns a path is not something upstream's
    build can express, so nothing upstream retires it.
  - *It globs now, so whatever upstream's `client/etc` holds is packaged* —
    with one exception carved out of the server's half.
  - *Now the `install -d` goes and the glob keeps packaging whatever upstream
    makes* — the `%exclude` stays behind when it does.

  Written down because nothing would catch it: `docs-drift.yml` runs
  `compensations.sh` and `docs.sh`, and neither reads prose against the spec.
  Until #66 merges all three are correct, which is why they are not being
  edited now.

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
- **The server's identity is pinned too early, and every packaging works
  around it.** *Not ours to fix; worth sending upstream.* `configure.server`
  asks for `XYMONHOSTNAME` and bakes it into `xymonserver.cfg` at **configure**
  time, so a source install carries the build machine's name. Each packaging
  compensates differently: `debian/rules:28` passes `XYMONHOSTNAME=localhost`
  rather than bake a wrong answer, and this spec's `%post` rewrites it at
  install time, which is later and closer to right.

  The client has no such problem: `client/runclient.sh:19` resolves
  `MACHINEDOTS` from `uname -n` at every start. And the fallback the server
  would need already exists — `common/xymoncmd.c:47-64` derives the name from
  `HOSTNAME`, then `uname()`, then `uname -n` — but it fires only when
  `MACHINEDOTS` is unset, and `xymonserver.cfg.DIST:79` always sets it from
  `XYMONSERVERHOSTNAME`, which always has a value. The config pre-empts it
  every time.

  **Where it bites here:** an image. `%post` in a `Dockerfile` runs in the
  builder, so the value frozen into the layer is the build sandbox's. Observed:
  a server built that way came up as `buildkitsandbox`, logged
  `MACHINE='xy-snap' not listed in hosts.cfg, dropping xymond status`, and
  wrote its RRDs under the builder's name. Installed inside a *running*
  container instead, `%post` reads the real hostname and everything is
  correct — which is what README *Trying a snapshot without a host*
  documents.

  **Why not fixed here.** Detecting a container in `%post` cannot work: at
  build time there is no correct value to write, because the runtime hostname
  does not exist yet. And the pinning itself is deliberate —
  [admin-guide.md](admin-guide.md) *Server tasks* says `%post` sets it on
  first install and to edit it if the host is renamed, because an identity
  that moves fragments the RRD history. Two of the three install paths, a
  host and a running container, get the right answer from it.

  **Upstream, and not as a patch from here.** No upstream pull request or
  issue addresses it (open and closed, searched by title and body). The change
  would be to stop the config pre-empting the existing fallback, which is a
  semantic change to what a server calls itself, and history is keyed on that.
  The evidence is worth sending — three packagings, three workarounds, a
  fallback already written and never reached — and the decision is the
  maintainers'. An issue, not a pull request.

  An image would meanwhile need an entrypoint that redoes the host-specific
  configuration at start, which is three lines and is where the answer first
  exists. Nothing here builds an image, so nothing here carries it: shipping
  that script in the package would put a file on every host where it means
  nothing, and an example nothing runs is an example that rots.

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
