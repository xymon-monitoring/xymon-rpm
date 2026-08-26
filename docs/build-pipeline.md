# The build pipeline

One workflow, `.github/workflows/build.yml`, builds every target, gates on the
tests, and publishes. It runs on pushes to `main`, on a nightly cron (upstream
drift), and on manual dispatch (any ref — see README *Building a branch or a
pull request*).

## The job graph

```
rpm (matrix: el8/9/10, fc43/44, stream9/10*, rawhide*, selinux)
 ├─ systemd-lifecycle ┐
 ├─ upgrade           ├─ publish   (needs all four; main / rel-* only)
 └─ monitoring        ┘
   (* = canary: allowed to fail, never published)
```

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

## Drift detection

Two nightly schedules (see [upstream.md](upstream.md) *Drift detection*):
`build.yml` rebuilds `main` so a moved install path goes red the next day, and
`docs-drift.yml` runs `docs.sh` to catch `upstream.md` drifting from reality.
