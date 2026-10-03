# The regression tests

The suites live in `tests/`. README *Testing* catalogues the ones that read a
built rpm — what each asserts and why. The three that guard text rather than
packages — `docs.sh`, `attribution.sh`, `compensations.sh` — are not there;
each carries its own reasoning in its header, and the table below says where
it runs. This file is the shape: which run where, and how to run one yourself.
The design is a cheap-to-expensive net — a break should fail at the cheapest
suite that can see it.

## Layered from cheap to expensive

| Suite | Reads / needs | Runs in |
| --- | --- | --- |
| `vercmp.sh` | the `Release` strings only | every `rpm` build |
| `packages.sh` | the rpms, uninstalled | every `rpm` build |
| `publish.sh` | a throwaway tree + key | every `rpm` build |
| `install.sh` | installs into the container | every `rpm` build |
| `systemd.sh` | a real PID 1 | `systemd-lifecycle` job |
| `upgrade.sh` | the **published** build, then this one | `upgrade` job |
| `monitoring.sh` | a running server + its client | `monitoring` job |
| `docs.sh` | `upstream.md` vs the source | `docs-drift.yml` (schedule) |
| `attribution.sh` | one text file | `attribution.yml` (pull requests, pushes to `main`) |
| `compensations.sh` | the spec, the two trackers, every document | `docs-drift.yml` (schedule) |

The first four read from the built rpms and run inside the container matrix.
The next three need PID 1 or a non-empty root, so they are separate jobs on
one EL + one Fedora target ([build-pipeline.md](build-pipeline.md)). `docs.sh`
guards the docs, not a build, so it runs on a schedule and never gates a
release. `attribution.sh` guards text rather than packages — a commit message,
a pull request title and body — so it has its own workflow for the same reason.
`compensations.sh` joins `docs.sh` in `docs-drift.yml`: it asserts that every
upstream pull request the spec cites is held by a tracker, which is how a
workaround becomes visible as removable on the day its pull request merges. It
also asserts the citation form, `xymon#NNN`, in the spec and in every document
— without which the first assertion is optional, since a bare number is simply
not seen, and in a document a bare one renders as a link to this repository's
own issue of that number. Neither of those two reads an rpm.

## Two that earn their place

- **`upgrade.sh`** is the only suite starting from a non-empty root, so the
  only one that exercises `%pretrans` (the layout migration).
- **`monitoring.sh`** is the only suite that checks the thing actually
  *monitors* — it asserts the server analyses its own client into `cpu`,
  `disk`, `memory`, `procs`, with the board read *before* any client runs so a
  query that always answers cannot pass. It caught a real bug immediately (the
  `localhost` vs `uname -n` host mismatch that made `xymond_client` silently
  drop reports).

## Running one locally

Each suite is a self-contained script over the built rpms. Build first
(README *Building locally*), then point a suite at the directory holding the
packages — `out/` when the argument is left off:

```sh
tests/packages.sh path/to/rpms/
```

`systemd.sh`, `upgrade.sh` and `monitoring.sh` want a real init — a container
with `systemd`, or a throwaway VM — because without PID 1 every `systemctl` is
swallowed by `|| :`. The `systemd-lifecycle` job in `build.yml` has a
container recipe that works outside CI too: an image with `systemd` as its
`CMD`, run `--privileged --cgroupns=host` with `/sys/fs/cgroup` mounted.

- **EL9:** `systemd.sh` installs `curl`, which conflicts with the
  `curl-minimal` the image ships, and the suite stops there. Run
  `dnf -y swap curl-minimal curl` in the container first. CI runs this suite
  on el10 and fc44 only, so it never meets the conflict.
- **Comparing against a build from before a change:** the published snapshot
  will not do. `publish` runs on every push to `main` that is not docs-only,
  so the snapshot is rebuilt from the merge that brought the change in. Build
  the earlier commit instead.
