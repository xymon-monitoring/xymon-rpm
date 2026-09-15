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
signing key, downloads every target's rpms, checks out the `gh-pages`
published tree, and runs `build/publish.sh` — which signs, sorts each package
into the stable or `xymon-snapshot` channel by its `Release` field, and
commits. A `concurrency` group serialises overlapping runs so two publishes
cannot race the `gh-pages` push. No key present (a fork) → build and test, skip
publish.

### Serving the tree from an artifact

Pages can serve an uploaded artifact instead of a branch, which would leave
this repository at about a megabyte and stop a contributor cloning the
published rpms along with the packaging. That change cannot be rehearsed —
`publish` never runs from a pull request — and it replaces the state store
`publish.sh` merges into, so a bug in it would remove the fallback at the
moment it was wanted. It lands in two halves.

The first half is in place: `publish` stages the tree without the clone's
`.git` and uploads it as a Pages artifact, while still writing and serving the
branch. Both steps are `continue-on-error`, and the deploy is the separate
`pages` job, because the `github-pages` environment can refuse a deployment and
a refusal blocks a whole job rather than a step — attached to `publish` it
would stop the publish.

`pages` fails until two repository settings change, and is expected to: Pages
still builds from the `gh-pages` branch rather than from a workflow, and the
environment's deployment branch policy still names `gh-pages` rather than
`main`, which is where the workflow runs. Until both move, the red job is the
only symptom and the served site is untouched.

The second half deletes the branch, once several nights have shown the artifact
carries the same tree.

### The branch itself

`gh-pages` carries no history: each publish replaces it with a single orphan
commit, force-pushed. Pages serves the tip alone, so the history was read by
nobody — and a signed rpm differs in every byte from the previous build of the
same package, so git could not compress it either. Left to accumulate it also
defeated `publish.sh`'s retention in silence, keeping every snapshot the
published tree had pruned.

## Drift detection

Two nightly crons guard against upstream and doc drift — the detail is in
[upstream.md](upstream.md) *Drift detection*.
