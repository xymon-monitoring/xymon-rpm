# The regression tests

The suites live in `tests/`. README *Testing* is the catalogue — what each
suite asserts and why. This file is the shape: which run where, and how to run
one yourself. The design is a cheap-to-expensive net — a break should fail at
the cheapest suite that can see it.

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

The first four read from the built rpms and run inside the container matrix.
The next three need PID 1 or a non-empty root, so they are separate jobs on
one EL + one Fedora target ([build-pipeline.md](build-pipeline.md)). `docs.sh`
guards the docs, not a build, so it runs on a schedule and never gates a
release.

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
(README *Building locally*), then point a suite at the packages, e.g.:

```sh
tests/packages.sh path/to/*.rpm      # or the layout each script documents
```

`systemd.sh`, `upgrade.sh` and `monitoring.sh` want a real init — a container
with `systemd`, or a throwaway VM — because without PID 1 every `systemctl` is
swallowed by `|| :`.
