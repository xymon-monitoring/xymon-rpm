# The build pipeline

One workflow, `.github/workflows/build.yml`, builds every target, gates on the
tests, and publishes. It runs on every push and pull request that changes more
than documentation, on a nightly cron (upstream drift), and on manual dispatch
(any ref — see README *Building a branch or a pull request*). The nightly
`previews.yml` dispatches it once per new xymon-experimental preview, with
`xymon_ref=preview-<milestone>-<n>`. A build of `main`, of a `rel-*` tag or of
a preview publishes; one of any other ref leaves artifacts only.

## The job graph

```
lint                               (no container; publish waits on it too)

rpm (matrix: el8/9/10, fc43/44, stream9/10*, rawhide*)
 ├─ systemd-lifecycle ┐
 ├─ upgrade           ├─ publish ── pages   (needs all five; main / rel-* / preview-* only)
 └─ monitoring        ┘
   (* = canary: allowed to fail, never published)
```

`lint` runs `shellcheck -S error` over every shell script this repository
owns, found by shebang — so `rpm/sources/xymonlaunch-run` is one of them and
the archived `rpm/terabithia/` is not. No container, a few seconds. The level
is `-S error` deliberately; `build.yml` says why, at the job.

`publish` waits on it, and not for the packages' sake — the matrix has tested
those. It is for `build/publish.sh` itself, the one script whose failure a user
meets. bash executes a file as it reads it, so a syntax error half way down
does not stop the script starting: it signs and copies part of a tree, then
exits 2, leaving the published repository in a state no test covers. The cost
is accepted knowingly — a new error-level check in some future shellcheck could
stop a publish — because a release held by a lint is recoverable in a way a
half-published repository is not.

`systemd-lifecycle` needs PID 1, `upgrade` a non-empty root, and `monitoring`
starts daemons that would disturb the install test, so they run as their own jobs on one EL + one Fedora target rather than
inside the container matrix.

## What the `rpm` job does, per target

1. **enable build repos** — EPEL/CRB on EL for `rrdtool-devel`, `c-ares-devel`
2. **checkout packaging** (full history — the packaging sha is half the version)
3. **checkout xymon source** — clones upstream, resolves `xymon_ref` (a branch,
   tag, sha, `pr/NNN`, or `preview-X.Y.Z-N`, fetched from xymon-experimental)
4. **compute version** — release, snapshot or preview `Release` string (README
   *Versioning*)
5. **create source tarball** — `git archive` of the checked-out HEAD; no tree is
   ever modified between clone and build (the "no patches" rule)
6. **parse the spec** — `rpmspec -P` (a lua `#` comment fails this)
7. **install builddeps**, **build** — `rpmbuild`
8. **test the built rpms** — `vercmp`, `packages`, `publish`, `install`
   (see [testing.md](testing.md))
9. **upload artifacts** — named `pub-<target>` or `canary-<target>`

## Publishing

The `publish` job gates on the four test jobs and `lint`, and only runs for `main`, a
dispatched `rel-*` tag (a tag build is the release flow), or a dispatched
`preview-*` tag from xymon-experimental. It imports the
signing key, downloads every target's rpms, checks out the published tree from
`xymon-monitoring/xymon-rpm-archive`, and runs `build/publish.sh` — which
signs, sorts each package into the stable, `xymon-snapshot` or `xymon-preview`
channel by its `Release` field, and rebuilds `xymon-preview-next` from the next
release's previews; the job then commits and pushes the tree. A `concurrency`
group serialises overlapping runs
so two publishes cannot race the push. No key present (a fork) → build and
test, skip publish.

The tree lives in its own repository so that cloning the packaging does not
fetch the rpms with it. Reaching another repository needs its own credential,
since `github.token` is scoped to the one running the workflow: a deploy key,
which reaches exactly that repository, belongs to no person and does not
expire ([signing.md](signing.md) *Rotating the archive deploy key*). The clone
has no fallback that starts empty — the archive is seeded, so a clone that
fails is a failure, and publishing on top of nothing would serve one run's
packages and drop every other build from the channel.

### Serving the tree from an artifact

Pages serves an artifact the `publish` job uploads — the published tree,
without the clone's `.git` — so a clone of this repository carries no rpms. A
failed upload fails `publish`. The deploy is its own `pages` job, because the
`github-pages` environment can refuse a deployment and a refusal blocks a whole
job rather than a step: attached to `publish` it would stop the publish.

Two repository settings govern it. The `github-pages` environment's deployment
branch policy must allow `main`, or the job fails outright (*branch "main" is
not allowed to deploy to github-pages due to environment protection rules*).
The Pages source must be GitHub Actions, or a deployment is accepted and
recorded while something else is served. If either setting is changed back the
`pages` job fails and the site stops being updated, which is the symptom to
look for.

### The archive

The published tree lives in `xymon-monitoring/xymon-rpm-archive`, which serves
nothing and exists to be cloned by the publish job and read by a person; it
moved there from this repository's `gh-pages` branch
([#37](https://github.com/xymon-monitoring/xymon-rpm/issues/37)).

A repository of its own, rather than keeping the branch or dropping the copy:
keeping `gh-pages` made every clone of this repository fetch the rpms, roughly
460 MB at a full retention window; dropping it needed a new state store and gave
up a copy of the published tree a person can check out and restore. Moving it
kept both, at the price of a credential, since `github.token` reaches only the
repository running the workflow. Unbounded growth was not the reason:
[#15](https://github.com/xymon-monitoring/xymon-rpm/issues/15) showed GitHub's
collection take the repository from 2.15 GiB to 41 MB in hours.

The archive carries no history: each publish replaces `main` with a single
orphan commit, force-pushed. Nothing reads an older one — a signed rpm differs
in every byte from the previous build of the same package, so git could not
compress the history either, and letting it accumulate defeated `publish.sh`'s
retention in silence, keeping every snapshot the published tree had pruned.

**The archive has a package before the site does**, by about three quarters of
a minute: `publish` pushes it as its last act, and `pages` is a separate job
that starts afterwards. Measured on one publish — archive at 20:37:12, Pages
deployment finished at 20:37:59. Verifying against the site in that window gets
a 404 for a file that exists, which is what to expect rather than a fault; read
the archive instead, at
`raw.githubusercontent.com/xymon-monitoring/xymon-rpm-archive/main/`.

That order is the safe one and not an accident. If a deployment fails, the tree
is already saved and the next publish resumes from it. Reversed — deploy, then
push — a failed push would leave the site ahead of the state store, and the
next publish would rebuild from a stale tree and unpublish packages. A reader
sees the previous tree, whole, for under a minute: the site is one artifact and
changes in one step, so metadata never points at files that are not there.

## Drift detection

Two nightly crons guard against upstream and doc drift — the detail is in
[upstream.md](upstream.md) *Drift detection*.
