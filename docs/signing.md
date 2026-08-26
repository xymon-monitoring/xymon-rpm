# Package signing

Packages and repository metadata are both signed. The shipped `.repo` file
sets `gpgcheck=1` (packages) and `repo_gpgcheck=1` (the metadata, i.e. the
package *list*), so `dnf` verifies that both came from this project and were
not altered in transit.

## The key

```
Xymon Project (RPM signing key)
RSA 4096, created 2026-07-31, expires 2029-07-30

BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

The public half is `RPM-GPG-KEY-xymon` in this repository, and the publish
job copies it into the published tree at `/RPM-GPG-KEY-xymon`. The
fingerprint above is also recorded in `README.md`: a fingerprint served
from the same host as the packages proves nothing on its own, so check the
key you fetch against a copy you trust.

The user id carries no email on purpose — there is no project mailbox, and
a wrong address would be baked into a key users trust for years. One can be
added later with `gpg --edit-key … adduid` without changing the fingerprint.

## Verifying as a user

The `xymon-release` package installs both the `.repo` file and the key
(into `/etc/pki/rpm-gpg/`), and is itself signed with this key, so adding
the repository needs no separate trust decision. Otherwise fetch the
`.repo` file directly:

```sh
curl -o /etc/yum.repos.d/xymon.repo \
  https://xymon-monitoring.github.io/xymon-rpm/xymon.repo
```

Either way, before installing, confirm the fingerprint of the imported key
matches the one above:

```sh
gpg --show-keys /etc/pki/rpm-gpg/RPM-GPG-KEY-xymon   # or the curled key
```

`dnf` then enforces both `gpgcheck` and `repo_gpgcheck` automatically.

## How signing happens in CI

The `publish` job in `.github/workflows/build.yml` does the signing:

1. It imports the private key from the `GPG_PRIVATE_KEY` repository secret
   and writes `%_gpg_name` (the imported key id) to `~/.rpmmacros`.
2. `build/publish.sh` runs `rpm --addsign` over every built package, then
   `createrepo_c` per channel/releasever/arch directory, then
   `gpg --detach-sign --armor` on each `repomd.xml` (this is what makes
   `repo_gpgcheck=1` possible).
3. The `xymon-release` bootstrap rpm is built and signed the same way.

The key carries **no passphrase**. CI cannot type one, so it would have to
live in a second secret beside the key — guarding nothing that reading the
first secret does not already give away. (Protecting a maintainer's local
keyring is a separate concern, best solved with a protected primary key and
an unprotected signing subkey exported to CI.)

If `GPG_PRIVATE_KEY` is unset, the publish job stops early with a notice
and publishes nothing, rather than failing.

**Who can sign:** anyone who can read the private key or change a workflow
here. In practice that is the read-access list of the private repository
below, plus anyone who can already change what gets built.

## Where the private half lives

- `rpm-signing/` in the private org repository
  [xymon-monitoring/private](https://github.com/xymon-monitoring/private),
  together with the revocation certificate and a copy of the public half —
  this is the copy that matters for continuity, since a repository secret
  cannot be read back out to renew, recover, or revoke the key;
- the `GPG_PRIVATE_KEY` secret in this repository, which CI imports;
- the generating maintainer's GnuPG keyring.

## Revocation

GnuPG generated a revocation certificate at key creation, stored as
`rpm-signing/xymon-rpm-signing.revocation.asc` in the private repository
(the original is under `~/.gnupg/openpgp-revocs.d/` on the generating
machine). It currently lives beside the key it revokes, which is
acceptable because reaching that repo already means being able to sign — a
copy held outside GitHub would still be an improvement.

**If the key is compromised:** publish the revocation certificate, generate
a replacement and load it into `GPG_PRIVATE_KEY`, ship an `xymon-release`
carrying both the revocation and the new key so installations learn of
both, then re-sign and re-publish anything that must stay installable.

## Renewing before expiry

Expiry stops *new* signatures only; already-signed packages stay valid. The
fingerprint does not change, so nothing on the user side needs updating.

```sh
gpg --edit-key "Xymon Project"
> expire            # choose a new period
> save
gpg --armor --export "Xymon Project" > RPM-GPG-KEY-xymon
```

Commit the refreshed public key.

## Generating a replacement key

```sh
cat > keyparams <<'EOF'
Key-Type: RSA
Key-Length: 4096
Key-Usage: sign
Name-Real: Xymon Project (RPM signing key)
Expire-Date: 3y
%no-protection
%commit
EOF
gpg --batch --generate-key keyparams && rm keyparams

gpg --armor --export "Xymon Project" > RPM-GPG-KEY-xymon
gpg --armor --export-secret-keys "Xymon Project" \
  | gh secret set GPG_PRIVATE_KEY --repo xymon-monitoring/xymon-rpm
```

RSA rather than ed25519 because EL8's rpm predates reliable EdDSA support
and EL8 is supported until 2029. Three years rather than never, so a leaked
key is not a problem forever. Piping the export straight into
`gh secret set` keeps the private key off disk and off screen.

A replacement changes the fingerprint, so update every copy of it: this file's
*The key* section, the README's *Installing* block, and `rpm/fingerprint`
(the value CI checks against).
