# Contributing to the Xymon RPM packaging

Patches are welcome. This file covers what is easy to get wrong because it is
not visible from the tree.

Fork, remotes and the pull-request flow are the same for every repository in
the organisation and are documented once, in the wiki: start with
[first-contribution.md](https://github.com/xymon-monitoring/xymon-wiki/blob/main/docs/contributing/git/first-contribution.md);
[git-setup.md](https://github.com/xymon-monitoring/xymon-wiki/blob/main/docs/contributing/git/git-setup.md)
has the remote configuration.

## Which repository

This is the first question, and it is the one most often answered wrong,
because three trees can look like the right place for the same fix.

**The rule: upstream provides mechanism and location, downstream provides
activation and policy.**

| what you are changing | where it goes |
|---|---|
| Xymon's behaviour, its build, what `make install` produces | `xymon-monitoring/xymon` |
| what an RPM installs, requires, starts, migrates or labels | here |
| the old `rpm/` directory inside `xymon-monitoring/xymon` | nowhere — it is unmaintained and builds nothing anyone ships |

A directory that Xymon's own configuration declares but its `Makefile` never
creates is an upstream gap, even though you meet it as a missing directory in
an RPM. Reloading a web server after dropping a configuration file into its
`conf.d` is policy: the service name, the init system and the decision are all
distribution business, and upstream cannot make it for every packager.

The middle case is the expensive one. A change to what `make install` produces
lands on Debian and FreeBSD at the same time as on this packaging, so it needs
those packagers told before it merges, not after. Say so in the pull request
rather than discovering it at release time.

[docs/upstream.md](docs/upstream.md) tracks the gaps this packaging compensates
for and the upstream pull requests that would close each one. A workaround
added here without an entry there is a workaround nobody will ever remove.

## Where a change gets written down

A fact belongs where its reader is, and every other place points at it rather
than repeating it. Copy a fact only when the second reader cannot reach the
first copy — a test asserting a string is a legitimate copy, because it fails
when the string changes.

| surface | who reads it | what it carries |
|---|---|---|
| pull request title | everyone scanning the list, and `git log --oneline` after a squash | the component, then what the change makes true |
| pull request description | the reviewer deciding | the defect, the mechanism, what a reviewer cannot infer, the evidence |
| commit message | whoever runs `git blame` years later, offline | what changed and why, in terms that stand alone |
| spec comment | whoever edits that scriptlet, without the pull request | why this and not the obvious alternative, and which upstream PR would delete it |
| `docs/` | a packager or a maintainer, with the tree open | how the pieces fit: the spec map, the pipeline, the tests, the upstream ledger |
| `README.md` | someone deciding whether to install these packages | what the packages are, how to add the repository, how versions are formed |
| test header and assertion text | whoever the test fails on | what it pins, and what was expected against what happened |
| `%description` in the spec | someone running `dnf info` | what the package is for, in two or three lines |

The longer form of this rule, and the companion rule on shortening prose
without losing what a reader needs, are in the source tree's
[CONTRIBUTING.md](https://github.com/xymon-monitoring/xymon/blob/main/CONTRIBUTING.md)
— they are the same rules for both repositories and are maintained there. Two
worth carrying in your head: shorten losslessly or not at all, and shorten
last, because text edited while the change is still moving ends up describing
the previous revision.

The cost of ignoring this is not length, it is drift: when one fact sits in two
places, one copy goes stale and nothing says which.

## Pull requests

Every change goes through a pull request. `main` here is **not** protected —
there is no ruleset and no required review, so nothing stops a direct push.
That is a gap rather than a policy, and until it is closed the rule is the
social one: open a pull request, and say in it if you merged your own.

A second reader is always the better outcome. Packaging fails in ways that are
invisible in a diff and expensive on a running host — a scriptlet that runs in
the wrong order, an upgrade path that works only from the version you happened
to have installed — so the bar for "obvious enough to self-merge" is lower here
than the size of the diff suggests.

How a change was written does not enter into it. Whoever opens the pull request
is its author, whatever helped them write it: they read every line, can say
what each part does and how it was checked, and answer for it. Responsibility
does not move to a tool.

- One change per pull request. A fix and the cleanup you noticed next to it are
  two pull requests.
- Say what you verified, and how. "Built and installed on el9" is useful;
  "should work" is not. If you could not test something, say that too — it is
  not held against you, and it tells a reviewer where to look.
- **Name the distribution you actually tested on.** CI builds AlmaLinux and
  Fedora containers. That is not RHEL, not SUSE, and not a machine with SELinux
  in enforcing mode, so a report from any of those is worth more than another
  green matrix.
- If your change fixes something a suite could have caught, adding the
  assertion is worth more than the fix. [docs/testing.md](docs/testing.md) says
  which suite it belongs in.
- Keep the description accurate as it evolves. A reviewer reading it after
  three force-pushes should not be reading the original plan.

### Titles

The title is the one line a reader gets in the pull request list and, after a
squash merge, in `git log --oneline`. Write it so that line is enough.

- Start with the component that changes, then a colon: a name the tree already
  uses — `spec:`, `publish:`, `tests:`, `docs:`, `ci:`, `build:`, `README:`, or
  a package or file this tree names (`xymon-release:`, `xymon.repo:`,
  `logrotate:`, `selinux:`). One plain name, unscoped. No `DRAFT:` or
  `follow-up:` — GitHub has a draft flag.
- After the colon, a complete sentence with a verb, in lower case. `reload a
  running httpd after installing the Apache config` says what happens; `httpd
  reload support` does not.
- Say what the change makes true, not only what it removes. When one behaviour
  replaces another, name both: `default to fping instead of the setuid
  xymonping`. The verb names the behaviour, not the kind of change — which is
  why `fix` and `add` so rarely fit: the diff already shows the kind.
- Keep the reason in the title when it fits in a clause.
- Anything that belongs in the description stays out of the title. A single
  parenthesis at the end may carry a reference — where the change came from,
  what it supersedes. `Fixes #N` goes in the description, which is where GitHub
  acts on it.
- Keep the sentence to 80 characters or fewer, so it reads whole in the list
  and in `git log --oneline`. A trailing reference may take the line past that.

### Descriptions

- Say what is wrong before what changes: the defect in a sentence, then the
  mechanism that fixes it. A reader who stops after two sentences should still
  know why the pull request exists.
- Carry what a reviewer cannot infer from the diff — a distribution floor, an
  ordering against an upstream pull request, a scriptlet deliberately left
  alone, something you could not test.
- Show the evidence, compactly. A before-and-after `rpm -q` line, a package
  listing, a measurement. A table of three rows says what three paragraphs say.
- Cite what can be checked. A claim about the tree carries `file:line`; a claim
  about another change carries its number, and upstream ones are written
  `xymon#411` so a reader knows which repository to open.

## Versioning

`Version` and `Release` are computed at build time from both git trees — the
upstream commit being packaged and the packaging commit — so neither is edited
by hand and `%changelog` stays empty. README *Versioning* has the form.

One rule follows from it and is absolute: **a published `Version`-`Release`
pair is immutable** (`build/publish.sh:78`). Two different builds producing the
same NEVRA is a versioning bug, not something to paper over by republishing.
Changing what an already-published name contains is the one failure a package
manager cannot recover from.

## Style

Match the file you are editing. The spec is one long file written in one voice;
a block that reads differently from the ones around it costs a reviewer more
than it saves you.

Two things the spec does deliberately, which look like noise until you need
them:

- **Every workaround names its upstream pull request in a comment.** That
  comment is what lets the workaround be deleted later by someone who was not
  there when it was written. A compensation added without one is permanent by
  accident.
- **The spec is commented for *why*, not *what*.** `docs/spec-structure.md` is
  the map of where things are, so a comment that restates the map goes stale in
  two places at once.

Shell in `build/` and `tests/` is POSIX-ish and runs under `set -eu`. It runs
in Fedora and EL containers, so GNU tools are available — but a test that
depends on one is pinning the container, not the packaging, and should say so.
