# Roadmap

The **live trackers already exist and are checked in CI**; don't duplicate
them here:

- upstream fixes that let the spec drop a workaround, and where each stands →
  [xymon-rpm#109](https://github.com/xymon-monitoring/xymon-rpm/issues/109)
  (a PR table, verified nightly by `docs.sh`)
- what the runtime shortfalls mean on a host → README *Known gaps*

This file is for what those don't cover: **decisions to make, and packaging
work with no upstream PR behind it.** Keep it short; move anything actionable
to a GitHub issue.

## Decisions

- **Review policy for this repo.** `main` is unprotected, so a change can merge
  with no second reviewer. That lets packaging iterate fast, and also lets
  self-authored work land unreviewed. Options: adopt upstream's required
  review; keep it open; or protect `main` but require review only for `rpm/`
  and `build/`, letting docs-only through (matching the "commit documentation
  separately" split). Decide deliberately.

  Two things to weigh. No merged pull request has carried a review, and
  consecutive audits of the contribution files each found problems in the
  pull requests before them: the kind a second reader catches, because an
  author checks what they meant rather than what they wrote. Against that,
  the repository now has an outside contributor, so a reviewer exists.

  **The disclosure rule waits on this.** CONTRIBUTING *Pull requests* asks an
  author to say in the pull request if they merged their own: a social rule
  standing in for the missing protection. An audit of the twenty-nine merged
  on 15 September found it followed in 2 of the 27 it binds. Required review
  would retire it rather than mend it, as there would be no self-merge to
  disclose. So its rewrite follows this decision and should not be patched
  ahead of it.
- **Whether to put the packages in Fedora, and through it EPEL.** RHEL itself is
  not a community path: Red Hat decides what it ships. "Official for RHEL"
  means EPEL in practice, and EPEL is built from Fedora, so the route is
  Fedora first and EPEL branches after: a review ticket, a sponsor for a first
  package, then dist-git and Koji. Xymon is in neither today (checked against
  Fedora's project API, where `nagios` answers and `xymon` and `hobbit` do not),
  so it is a new submission rather than taking one over.

  What it buys is what a user notices: no third-party repository to add, no
  `.repo` file, no key to trust. That is also the cost. This packaging
  iterates (versions derived from two git trees, a publish per commit, no
  hand-written changelog), and a distribution package is the opposite regime.
  The question under the question is whether one spec serves both or a
  submission is its own.

  The spec is closer than third-party specs usually are: SPDX licence, no
  obsolete tags, no patches, scriptlet `Requires(pre/post)`, sysusers with an
  EL8 fallback, every `%config` `noreplace`, and `Provides: %{name}-static` in
  the form the guidelines ask for. The one hard blocker, a build that ignored
  the distribution's flags, closed when `%build` took `%{optflags}`.

  Three things remain, and only one is a decision:
  - `%changelog` is empty because the version is derived; Fedora wants entries.
    One written at each release satisfies it without touching the model.
  - `Conflicts: xymon-client` between subpackages is what a review pushes back
    on hardest, and it is
    [deployment-strategies.md](deployment-strategies.md) rather than an
    oversight. Changing it changes the product, not the packaging. **This is
    the decision.**
  - `%pretrans` in lua is the layout migration. It goes once no supported
    upgrade starts from the old layout; 4.3.31-1, the first release, still
    carries it.
- **The eventual move upstream.** [upstream.md](upstream.md) intends to move
  the spec and workflow into `xymon-monitoring/xymon` once stable, leaving this
  repo as the publish target. Part of that is deciding the fate of upstream's
  own stale `rpm/` (2014, SysV) and `debian/` (2019) packagings.
  `xymon-monitoring/xymon-apt` (since 2026-11-07) rebuilds Debian's own
  package, not upstream's `debian/`.

- **The client's drop-in directories.** *Decided and done:* the spec creates
  them, and gives `clientlaunch.d` to the client package alone. Only the
  `install -d` is an interim override xymon#411 will delete.
  `clientlaunch.cfg` and `xymonclient.cfg` each end in
  `optional directory @XYMONHOME@/etc/<name>`, and nothing created either.
  `optional` means nothing fails: a drop-in file is silently never read,
  which is how it surfaced as xymon#522 rather than as a crash.

  What decided it was the cost of waiting. With no directory, the only way to
  add a client task is to edit `clientlaunch.cfg`, which ships
  `%config(noreplace)`. An edited copy stops following upstream: on the day
  the shipped file changes (rare, not every snapshot), rpm leaves the new one
  beside it as a `.rpmnew` to merge by hand. From the first edit onward the
  host is on its own copy and no upgrade reaches it. With the directory, a
  customisation is a file of the admin's own and the shipped config keeps
  upgrading.

  It was not theoretical. xymon#522 asked for `clientlaunch.d` (only, not
  `xymonclient.d`), from someone who met the gap on an installed system. It
  patched `rpm/xymon.spec` inside `xymon-monitoring/xymon`, the unmaintained
  2014 spec that [CONTRIBUTING](../CONTRIBUTING.md) *Which repository* says is
  reviewed by nobody and shipped to nobody: the reason that rule exists, in
  one example. Its author closed it to re-file here, and it landed as
  [xymon-rpm#66](https://github.com/xymon-monitoring/xymon-rpm/pull/66).

  `%files` globs `/etc/xymon-client`, as the server half always has, so
  whatever upstream's `client/etc` holds is packaged. A list would not do:
  `check-files` lists `-type f -o -type l`, so an unpackaged *directory* is
  never reported, and the package would ship without xymon#411's directories
  with the build still green. When xymon#411 merges, the `install -d` goes and
  the glob keeps packaging whatever upstream makes.

  The one exception is `clientlaunch.d`, which `%files` excludes from the
  server package. A server reads its task list from `tasks.cfg` and never
  opens `clientlaunch.cfg`, so a drop-in beside the server's copy would be
  silently unused; extra server tasks belong in `tasks.d`. The `%exclude` is
  permanent: which of two packages owns a path is not something upstream's
  build can express, so nothing upstream retires it.

## Packaging work (no upstream PR)

- **Reconcile the SELinux `.te` with `%posttrans`.** The modules still reference
  `/var/cache/xymon`, which this layout does not use; the real labeling is in
  `%posttrans` ([selinux.md](selinux.md)).
- **Validate on more enforcing hosts, and on genuine RHEL and OracleLinux.**
  SELinux is validated on AlmaLinux 8, 9 and 10 and Fedora 44; CI compiles
  the policy but never runs enforcing. `mls` is unsupported: it would need a
  policy with domains of its own for the daemons ([selinux.md](selinux.md)).
  CI builds on AlmaLinux, a RHEL rebuild, which cannot surface a symbol RHEL
  lacks; real RHEL/OL testing is a standing gap. Recruit downstream testers.
- **The server's identity is pinned too early, and every packaging works
  around it.** *Not ours to fix; worth sending upstream.* `configure.server`
  asks for `XYMONHOSTNAME` and bakes it into `xymonserver.cfg` at **configure**
  time, so a source install carries the build machine's name. Each packaging
  compensates differently: `debian/rules:28` passes `XYMONHOSTNAME=localhost`
  rather than bake a wrong answer, and this spec's `%post` rewrites it at
  install time, which is later and closer to right.

  The client has no such problem: `client/runclient.sh:19` resolves
  `MACHINEDOTS` from `uname -n` at every start. The fallback the server
  would need already exists: `common/xymoncmd.c:47-63` derives the name from
  `HOSTNAME`, then `uname()`, then `uname -n`. But it fires only when
  `MACHINEDOTS` is unset, and `xymond/etcfiles/xymonserver.cfg.DIST:80`
  always sets it from `XYMONSERVERHOSTNAME`, which always has a value. The
  config pre-empts it every time.

  **Where it bites here:** an image. `%post` in a `Dockerfile` runs in the
  builder, so the value frozen into the layer is the build sandbox's. Observed:
  a server built that way came up as `buildkitsandbox`, logged
  `MACHINE='xy-snap' not listed in hosts.cfg, dropping xymond status`, and
  wrote its RRDs under the builder's name. Installed inside a *running*
  container, `%post` reads the real hostname and everything is correct, as
  README *Trying a snapshot without a host* documents.

  **Why not fixed here.** Detecting a container in `%post` cannot work: at
  build time there is no correct value to write, because the runtime hostname
  does not exist yet. And the pinning itself is deliberate: an identity that
  moves fragments the RRD history, so `%post` sets it on first install and
  [admin-guide.md](admin-guide.md) *Server tasks* says to edit it if the host
  is renamed. Two of the three install paths, a host and a running container,
  get the right answer from it.

  **Upstream, and not as a patch from here.** No upstream pull request or
  issue addresses it (open and closed, searched by title and body). The change
  would be to stop the config pre-empting the existing fallback, a semantic
  change to what a server calls itself, and history is keyed on that.
  The evidence is worth sending (three packagings, three workarounds, a
  fallback already written and never reached), and the decision is the
  maintainers'. An issue, not a pull request.

  An image would meanwhile need an entrypoint that redoes the host-specific
  configuration at start: three lines, where the answer first exists.
  Nothing here builds an image, so nothing here carries it. Shipping that
  script in the package would put a file on every host where it means
  nothing, and an example nothing runs is an example that rots.

- **Tests the last changes lack.** The old-layout upgrade through
  `Obsoletes` ([xymon-rpm#119](https://github.com/xymon-monitoring/xymon-rpm/pull/119))
  was checked by hand only. `tests/upgrade.sh:59` upgrades from the snapshot
  channel even on a release build, so a `4.3.31-2` re-release would be
  tested against a newer 4.3.32 snapshot. Two upstream commits in the same
  minute still order by sha (`.github/workflows/build.yml:247-251`).
  `tests/publish.sh` copies a single package, so it cannot see half a build
  pruned.
- **A milestone closed without a release keeps its previews.** Retention
  drops a milestone's previews once its release is in the stable channel.
  xymon-experimental retires a closed milestone's branches but not its
  preview releases, so one closed unreleased stays in `xymon-preview` (and in
  Homebrew) until removed by hand. 4.3.33's previews were removed that way
  in Nov 2026, though its milestone stays open.
- **Watch the signing key expiry** ([signing.md](signing.md) *Renewing before
  expiry*).

## Tracked elsewhere (pointers, not tasks)

- Enabling distribution hardening — the Debian `CPPFLAGS` gap,
  [xymon#444](https://github.com/xymon-monitoring/xymon/issues/444)
- The `SIGHUP` relay to the daemons —
  [xymon#172](https://github.com/xymon-monitoring/xymon/pull/172) (README
  *Known gaps*); `/run/xymon` itself is in use since xymon#219 merged
- Consuming a merged upstream feature — one spec PR each, e.g.
  [xymon-rpm#4](https://github.com/xymon-monitoring/xymon-rpm/pull/4) once
  4.3.32, which carries
  [xymon#414](https://github.com/xymon-monitoring/xymon/pull/414), is released
