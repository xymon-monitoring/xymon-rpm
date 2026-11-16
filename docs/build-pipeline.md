# The build pipeline

One workflow, `.github/workflows/build.yml`, builds every target, gates on the
tests, and publishes. It runs on:

- every push and pull request that changes more than documentation;
- a nightly cron, `17 0 * * *`, which catches upstream drift;
- manual dispatch, for any ref (README *Building a branch or a pull request*).

The nightly `previews.yml` (`47 1 * * *`) dispatches it too, for each
xymon-experimental milestone whose build is not in the archive yet:

- with no `rel-<milestone>` tag in xymon: its newest published preview, as
  `xymon_ref=preview-<milestone>-<n>`;
- with the tag: `xymon_ref=rel-<milestone>`, until the stable channel holds
  it. Nothing else starts a release build; xymon's release flow does not reach
  this repository.

A failed build is dispatched again the next day, as the archive records
successes alone.

A build of `main`, of a `rel-*` tag or of a preview publishes; one of any
other ref leaves artifacts only.

## The job graph

```
lint                               (no container; publish waits on it too)

rpm (matrix: el8/9/10, fc43/44, stream9/10*, fedora-rawhide*)
 ├─ systemd-lifecycle ┐
 ├─ upgrade           ├─ publish ── pages   (needs all five; main / rel-* / preview-* only)
 └─ monitoring        ┘
   (* = canary: allowed to fail, never published)
```

`lint` runs `shellcheck -S error` over every shell script this repository
owns, found by shebang. So `rpm/sources/xymonlaunch-run` is linted and the
archived `rpm/terabithia/` is not. It needs no container and takes seconds.
Why `error` and not `warning` is at `build.yml:88-97`.

`publish` waits on `lint` for the sake of `build/publish.sh`, not the packages,
which the matrix has tested. That script is the one whose failure a user
meets. bash executes a file as it reads it, so a syntax error half way down
does not stop the script starting. It signs and copies part of a tree, then
exits 2, leaving the published repository in a state no test covers. The cost
is accepted knowingly: a new error-level check in a future shellcheck could
stop a publish. A release held by a lint is recoverable; a half-published
repository is not.

Three test jobs run outside the container matrix, on `el10` and `fc44` only:
`systemd-lifecycle` needs PID 1, `upgrade` a non-empty root, and `monitoring`
starts daemons that would disturb the install test.

Every job stops after 30 minutes. The slowest takes about 6; GitHub's own
limit is 6 hours, which is how long a hung distribution mirror could hold a
job, and every merge waiting on it, without an error. A job stopped this way
fails visibly, and re-running it is the fix. For `publish` it is no worse than
any other failure: the tree reaches users only through the archive push near
its end.

## What the `rpm` job does, per target

1. **enable build repos** — EPEL/CRB on EL for `rrdtool-devel`, `c-ares-devel`
2. **checkout packaging** (full history — the packaging sha is half the version)
3. **checkout xymon source** — resolves `xymon_ref`
   ([upstream.md](upstream.md) *How the upstream ref is selected*)
4. **compute version** — release, snapshot or preview `Release` string (README
   *Versioning*)
5. **create source tarball** — `git archive` of the checked-out HEAD (the
   "no patches" rule), made as upstream's release tarball is, so a release's
   SRPM carries that tarball
6. **parse the spec** — `rpmspec -P` (a lua `#` comment fails this)
7. **install builddeps**, **build** — `rpmbuild`
8. **test the built rpms** — `vercmp`, `packages`, `publish`, `install`
   (see [testing.md](testing.md))
9. **upload artifacts** — named `pub-<target>` or `canary-<target>`

## Publishing

The `publish` job needs all five jobs above. It runs only for `main`, a
dispatched `rel-*` tag (the release flow), or a dispatched `preview-*` tag from
xymon-experimental (`build.yml:512-519`). In order, it:

1. refuses a `preview-*` tag whose xymon-experimental release is a draft or
   missing. The tag is pushed before the release is published, and a manual
   dispatch can name any tag (`build.yml:536-553`);
2. checks out `main`'s tip, not the run's sha. A run queued behind a newer one
   would otherwise regenerate `xymon.repo` and `index.html` from an older tree
   and force-push them over it (`build.yml:555-570`);
3. imports the signing key. With no key (a fork), it stops here: build and
   test, skip publish;
4. downloads every `pub-*` artifact and clones the published tree from
   `xymon-monitoring/xymon-rpm-archive`;
5. runs `build/publish.sh`, which signs, sorts each package into the stable,
   `xymon-snapshot` or `xymon-preview` channel by its `Release` field, and
   rebuilds `xymon-preview-next` from the next release's previews. The job then
   adds the key, `xymon.repo`, the `xymon-release` package and the indexes;
6. commits and force-pushes the tree, then uploads it as the Pages artifact.

A `concurrency` group serialises overlapping runs, so two publishes cannot race
the push.

The tree lives in its own repository so that cloning the packaging does not
fetch the rpms with it. Reaching another repository needs its own credential,
since `github.token` is scoped to the one running the workflow. A deploy key
reaches exactly that repository, belongs to no person and does not expire
([signing.md](signing.md) *Rotating the archive deploy key*). The clone has no
fallback that starts empty. The archive is seeded, so a failed clone is a
failure; publishing on top of nothing would serve one run's packages and drop
every other build from the channel.

### Serving the tree from an artifact

Pages serves an artifact the `publish` job uploads: the published tree,
without the clone's `.git`. So a clone of this repository carries no rpms. A
failed upload fails `publish`. The deploy is its own `pages` job, because the
`github-pages` environment can refuse a deployment, and a refusal blocks a
whole job rather than a step. Attached to `publish`, it would stop the publish.

Two repository settings govern it. The `github-pages` environment's deployment
branch policy must allow `main`, or the job fails outright (*branch "main" is
not allowed to deploy to github-pages due to environment protection rules*).
The Pages source must be GitHub Actions, or a deployment is accepted and
recorded while something else is served. If either setting is changed back,
the symptom is a failing `pages` job and a site that stops being updated.

### The archive

The published tree lives in `xymon-monitoring/xymon-rpm-archive`. It serves
nothing: the publish job clones it, and a person can read it. It moved there
from this repository's `gh-pages` branch
([#37](https://github.com/xymon-monitoring/xymon-rpm/issues/37)).

Why a repository of its own, rather than keeping the branch or dropping the
copy: keeping `gh-pages` made every clone of this repository fetch the rpms,
roughly 460 MB at a full retention window. Dropping it needed a new state store
and gave up a copy of the published tree a person can check out and restore.
Moving it kept both, at the price of the credential above. Unbounded growth was
not the reason:
[#15](https://github.com/xymon-monitoring/xymon-rpm/issues/15) showed GitHub's
collection take the repository from 2.15 GiB to 41 MB in hours.

The archive carries no history: each publish replaces `main` with a single
orphan commit, force-pushed. Nothing reads an older commit. A signed rpm
differs in every byte from the previous build of the same package, so git
could not compress the history either. Left to accumulate, it defeated
`publish.sh`'s retention in silence, keeping every snapshot the tree had
pruned.

**The archive has a package before the site does**, by about three quarters
of a minute. `publish` pushes the archive before it uploads the Pages artifact,
and `pages` is a separate job that starts afterwards. On one measured publish,
the archive landed at 20:37:12 and the Pages deployment finished at 20:37:59.
Verifying against the site in that window gets a 404 for a file that exists.
That is expected, not a fault: read the archive instead, at
`raw.githubusercontent.com/xymon-monitoring/xymon-rpm-archive/main/`.

That order is deliberate, because it is the safe one. If a deployment fails,
the tree is already saved and the next publish resumes from it. Reversed, a
failed push would leave the site ahead of the state store, and the next
publish would rebuild from a stale tree and unpublish packages. Meanwhile a
reader sees the previous tree, whole: the site is one artifact and changes in
one step, so metadata never points at files that are not there.

## Drift detection

Two nightly crons guard against upstream and doc drift — the detail is in
[upstream.md](upstream.md) *Drift detection*.
