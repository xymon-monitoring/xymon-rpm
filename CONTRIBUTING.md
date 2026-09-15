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
| something that belongs upstream, which upstream has not landed yet | here, as an interim override that names the upstream pull request |
| the old `rpm/` directory inside `xymon-monitoring/xymon` | nowhere — it is unmaintained and builds nothing anyone ships |

That last row is about today. [docs/upstream.md](docs/upstream.md) *Where the
packaging should eventually live* intends to move this packaging into that
repository once the spec is stable, and deciding what becomes of its stale
`rpm/` and `debian/` is part of that move. Until it happens, a packaging change
sent there is reviewed by nobody and shipped to nobody.

A directory that Xymon's own configuration declares but its `Makefile` never
creates is an upstream gap, even though you meet it as a missing directory in
an RPM. Reloading a web server after dropping a configuration file into its
`conf.d` is policy: the service name, the init system and the decision are all
distribution business, and upstream cannot make it for every packager.

The middle case is the expensive one. A change to what `make install` produces
lands on Debian and FreeBSD at the same time as on this packaging, so it needs
those packagers told before it merges, not after. Say so in the pull request
rather than discovering it at release time.

### When upstream is right but not yet available

The rule says where a fix belongs, not when you can have it. A gap that belongs
upstream may be compensated here in the meantime — that is a good part of what
this packaging is for — on one condition: **the compensation names the upstream
pull request that will delete it**, in the spec comment beside it and in
[docs/upstream.md](docs/upstream.md) *Gaps sent back upstream*. That comment is
what lets someone who was not there remove the workaround later. Without it,
the override is not interim, it is a permanent divergence nobody will recognise
as removable.

### The boundary moves

Which side a thing belongs to is dated, not settled. A compensation is
downstream because upstream does not offer the mechanism *today*; the day its
pull request merges, the same code becomes divergence. So the table does not
classify once and for all — it records where the line runs now.

Two checks watch that, nightly, from opposite ends. `tests/docs.sh` reads the
*Gaps sent back upstream* table and checks each pull request's real state: when
one merges, the drift check goes red — not because something broke, but because
a compensation just stopped being one. `tests/compensations.sh` takes the
condition above and checks it the other way, that every `xymon#NNN` the spec
cites is still held by a tracker — so a citation the merged proposal left
behind is named rather than waiting for someone to read the spec.

## Where to file an issue

Report where you met the problem, not where the fix belongs — telling those
apart is often the work the issue exists to do.

- It went wrong installing, upgrading, starting, or in what a package put on
  disk → **here**.
- It went wrong in Xymon itself, however you installed it →
  **`xymon-monitoring/xymon`**.

Triage is where the rule above applies, and it is the opportunity a report
creates: understanding it is the only moment anyone knows enough to place the
fix. Write it where it belongs, not where the issue happened to land — the
repository that iterates fastest is the tempting one, and taking it is how a
downstream accumulates divergence nobody decided on. The issue can stay with
its reporter; say in it which repository took the work, and why.

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
- **Say which side of the boundary the change is on, and why.** Not a formality:
  it is the question most often answered wrong, and answering it in writing is
  what stops a fix landing here because here is convenient. If it is an interim
  override, name the upstream pull request that will delete it.
- **Name the documents the change makes stale, or say that none does.** A rule
  lives in a document and is proved in a pull request: the pull request is read
  once, by a reviewer deciding, and the document is read by everyone
  afterwards. A change that rewrites a rule and explains itself only here
  leaves the document stating the old one, and nothing catches that —
  `tests/docs.sh` and `tests/compensations.sh` each watch one narrow claim, and
  no check reads prose against behaviour. Grepping the tree for the behaviour
  you changed is the whole cost.
- Carry what a reviewer cannot infer from the diff — a distribution floor, an
  ordering against an upstream pull request, a scriptlet deliberately left
  alone, something you could not test.
- Show the evidence, compactly. A before-and-after `rpm -q` line, a package
  listing, a measurement. A table of three rows says what three paragraphs say.
- Cite what can be checked. A claim about the tree carries `file:line`; a claim
  about another change carries its number, and upstream ones are written
  `xymon#411` so a reader knows which repository to open.

## Versioning

README *Versioning* has the scheme and the reason for it, including why a
published NEVRA is never rewritten. What it means for you, in three
prohibitions:

- Do not edit `Version` or `Release`. Both are computed at build time from the
  two git trees.
- Do not write a `%changelog` entry. It stays empty because there is no
  hand-written version for it to describe.
- Do not republish a NEVRA. Two builds producing the same one is a versioning
  bug to fix, not something to paper over. `build/publish.sh:81` will not
  overwrite a published file — it leaves the first copy in place and says so,
  so the second build's package is silently not the one users get.

## Style

Match the file you are editing. The spec is one long file written in one voice;
a block that reads differently from the ones around it costs a reviewer more
than it saves you.

One thing the spec does deliberately, which looks like noise until you need it:
**it is commented for *why*, not *what*.** `docs/spec-structure.md` is the map
of where things are, so a comment that restates the map goes stale in two
places at once. The other rule about spec comments — that a workaround names
the upstream pull request that will delete it — is in *Which repository*
above, because it is a condition on the override, not a matter of style.

Shell is POSIX-ish and runs under `set -eu`. It does not live only in `build/`
and `tests/`: `rpm/sources/xymonlaunch-run` is a shell script the packages
ship, which is why the `lint` job finds scripts by shebang rather than by
`*.sh`. That job runs `shellcheck -S error`, which the tree passes today;
`build.yml` says why that level and not `warning`.

Test scripts run in Fedora and EL containers, so GNU tools are available — but
a test that depends on one is pinning the container, not the packaging, and
should say so.
