# The regression tests

The suites live in `tests/`. README *Testing* says what each asserts and why,
except `attribution.sh`. The three that guard text rather than packages,
`docs.sh`, `attribution.sh` and `compensations.sh`, carry their full reasoning
in their headers. This file is the shape: which suite runs where, and how to
run one yourself. The design is a net from cheap to expensive: a break should
fail at the cheapest suite that can see it.

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
| `docs.sh` | `upstream.md` and the tracking issue vs the source | `docs-drift.yml` |
| `attribution.sh` | one text file | `attribution.yml`: pull requests, pushes to `main` |
| `compensations.sh` | the specs, the tracking issue, README *Known gaps*, every document | `docs-drift.yml` |

The first four run inside the container matrix. The next three are separate
jobs on `el10` and `fc44`; [build-pipeline.md](build-pipeline.md) *The job
graph* says why.

The last three read no rpm, so they run on workflows of their own and never
gate a release. `docs-drift.yml` runs nightly (`47 0 * * *`), on dispatch, and
on pushes to `main` touching a document, a spec, a checker or the workflow
itself (`docs-drift.yml:27-38`). `attribution.sh` checks a commit message, or
a pull request's title and body.

`compensations.sh` asserts that every upstream pull request the specs cite is
held by a tracker. That is how a workaround becomes visible as removable on the
day its pull request merges. It also asserts the citation form, `xymon#NNN`, in
the specs and in every document. Without it the first assertion is optional,
since a bare number is not seen. In a document, a bare one also renders as a
link to this repository's own issue of that number.

## Two that earn their place

- **`upgrade.sh`** is the only suite starting from a non-empty root, so the
  only one that exercises `%pretrans` (the layout migration). It upgrades from
  the snapshot channel, so a preview build skips it: a preview is another line
  and would read as a downgrade. A preview's packaging is main's, tested by the
  snapshot builds.
- **`monitoring.sh`** is the only suite that checks the thing actually
  *monitors*. It asserts the server analyses its own client into `cpu`,
  `disk`, `memory` and `procs`. The board is read *before* any client runs, so
  a query that always answers cannot pass. It caught a real bug on its first
  run: `hosts.cfg` named `localhost` while the client reported under
  `uname -n`, so `xymond_client` silently dropped every report.

## Running one locally

Each suite is a self-contained script over the built rpms. Build first
(README *Building locally*), then point a suite at the directory holding the
packages — `out/` when the argument is left off:

```sh
tests/packages.sh path/to/rpms/
```

`systemd.sh` wants a real init, a container with `systemd` or a throwaway VM,
because without PID 1 every `systemctl` is swallowed by `|| :`. The
`systemd-lifecycle` job in `build.yml` has a container recipe that works
outside CI too: an image with `systemd` as its `CMD`, run
`--privileged --cgroupns=host` with `/sys/fs/cgroup` mounted. `upgrade.sh` and
`monitoring.sh` need no init: CI runs them in a plain container
(`build.yml:361-371`, `405-415`). `upgrade.sh` needs `curl` and network access to the
published repository; `monitoring.sh` needs `procps-ng`.

- **EL9:** `systemd.sh` installs `curl`, which conflicts with the
  `curl-minimal` the image ships, and the suite stops there. Run
  `dnf -y swap curl-minimal curl` in the container first. CI runs this suite
  on el10 and fc44 only, so it never meets the conflict.
- **Comparing against a build from before a change:** the published snapshot
  will not do. `publish` runs on every push to `main` that is not docs-only, so
  the snapshot is rebuilt from the merge that brought the change in. Build the
  earlier commit instead.
