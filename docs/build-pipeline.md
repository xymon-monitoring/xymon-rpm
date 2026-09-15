# The build pipeline

One workflow, `.github/workflows/build.yml`, builds every target, gates on the
tests, and publishes. It runs on pushes to `main`, on a nightly cron (upstream
drift), and on manual dispatch (any ref — see README *Building a branch or a
pull request*).

## The job graph

```
lint                               (no container; publish waits on it too)

rpm (matrix: el8/9/10, fc43/44, stream9/10*, rawhide*, selinux)
 ├─ systemd-lifecycle ┐
 ├─ upgrade           ├─ publish ── pages   (needs all five; main / rel-* only)
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

`systemd-lifecycle`, `upgrade` and `monitoring` need PID 1 or a non-empty
root, so they run as their own jobs on one EL + one Fedora target rather than
inside the container matrix.

## What the `rpm` job does, per target

1. **enable build repos** — EPEL/CRB on EL for `rrdtool-devel`, `c-ares-devel`
2. **checkout packaging** (full history — the packaging sha is half the version)
3. **checkout xymon source** — clones upstream, resolves `xymon_ref` (a branch,
   tag, sha, or `pr/NNN`)
4. **compute version** — release vs snapshot `Release` string (README *Versioning*)
5. **create source tarball** — `git archive` of the checked-out HEAD; no tree is
   ever modified between clone and build (the "no patches" rule)
6. **parse the spec** — `rpmspec -P` (a lua `#` comment fails this)
7. **install builddeps**, **build** — `rpmbuild`
8. **test the built rpms** — `vercmp`, `packages`, `publish`, `install`
   (see [testing.md](testing.md))
9. **upload artifacts** — named `pub-<target>` or `canary-<target>`

## Publishing

The `publish` job gates on all four test jobs and only runs for `main` or a
dispatched `rel-*` tag (a tag build is the release flow). It imports the
signing key, downloads every target's rpms, checks out the published tree from
`xymon-monitoring/xymon-rpm-archive`, and runs `build/publish.sh` — which
signs, sorts each package into the stable or `xymon-snapshot` channel by its
`Release` field, and commits. A `concurrency` group serialises overlapping runs
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

Pages can serve an uploaded artifact instead of a branch, which would leave
this repository at about a megabyte and stop a contributor cloning the
published rpms along with the packaging. That change cannot be rehearsed —
`publish` never runs from a pull request — and it replaces the state store
`publish.sh` merges into, so a bug in it would remove the fallback at the
moment it was wanted. So it was done in a step that could be stopped at.

That step is in place: `publish` stages the tree without the clone's
`.git` and uploads it as a Pages artifact, while still writing the
branch. Both steps are `continue-on-error`, and the deploy is the separate
`pages` job, because the `github-pages` environment can refuse a deployment and
a refusal blocks a whole job rather than a step — attached to `publish` it
would stop the publish.

Two repository settings govern this, and they do different things. The
`github-pages` environment's deployment branch policy decides whether the job
may deploy at all: it named only `gh-pages` while the workflow runs on `main`,
so the job failed outright — *branch "main" is not allowed to deploy to
github-pages due to environment protection rules* — until `main` was added.
The Pages source decides what is *served*. It is GitHub Actions now, so the
artifact answers a request; while it was the `gh-pages` branch, a deployment
from `main` was accepted and recorded and the branch build answered instead.

That split gave the change the only rehearsal available to it, since `publish`
never runs from a pull request: with the branch policy open and the source
still the branch, the artifact path ran green end to end while users were
served exactly as before. The switch was then checked by hashing `repomd.xml`
off the live site against the blob the branch held, which matched, and by
downloading a signed rpm from it.

If either setting is changed back the `pages` job fails and the site stops
being updated, which is the symptom to look for.

### The archive

The published tree moved out of this repository's `gh-pages` branch and into
`xymon-monitoring/xymon-rpm-archive`, which serves nothing and exists to be
cloned by the publish job and read by a person. `gh-pages` is no longer
written; it is left frozen at the tree as it stood when the archive took over,
and deleting it is a separate act whose only effect is to make a clone of this
repository cheap.

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
