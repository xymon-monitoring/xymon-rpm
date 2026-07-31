# Package signing

Packages and repository metadata are signed so `dnf` can verify they came
from this project and were not modified in transit. Both `gpgcheck` and
`repo_gpgcheck` are enabled in the shipped `.repo` file, so the package
*list* is verified as well as the packages themselves.

## The current key

```
Xymon Project (RPM signing key)
RSA 4096, created 2026-07-31, expires 2029-07-30

BD24 FB87 154D 561B 66F6  66DF 639D E923 AA08 904A
```

The public half is `RPM-GPG-KEY-xymon` in this repository and is served at
`/RPM-GPG-KEY-xymon` alongside the packages. **Check the fingerprint above
against the key you fetched** — a fingerprint that only lives on the same
server as the packages proves nothing, which is why it is also recorded
here and in the README.

The user id deliberately carries no email address. There is no project
mailbox to point at, and inventing one would bake a wrong address into a
key users trust for years. An address can be added later with
`gpg --edit-key … adduid` **without changing the fingerprint**.

## Where the private half lives

Three places:

- `rpm-signing/` in the private organisation repository
  [xymon-monitoring/private](https://github.com/xymon-monitoring/private),
  together with the revocation certificate and a copy of the public half
- the `GPG_PRIVATE_KEY` secret in this repository, which the publish job
  imports
- the generating maintainer's GnuPG keyring

The first of those is the one that matters for continuity. A repository
secret cannot be read back out, so GitHub's copy lets CI keep signing but
would not let anyone renew, recover or revoke the key. Without the copy in
`private`, losing one laptop would mean a key nobody could ever retire —
which is the failure mode xymon-monitoring/xymon-problems#5 describes, and
what makes the Terabithia and bitweaver repositories fragile.

The trade is that **everyone with read access to `private` can sign as the
Xymon project**. That access list is the real definition of who can sign,
and should be reviewed on that basis.

### There is no passphrase, on purpose

The obvious instinct is to protect the key with a passphrase. In this
design it buys nothing: CI cannot type one, so it would have to be stored
in a second repository secret directly beside the key. Anyone able to read
`GPG_PRIVATE_KEY` can read `GPG_PASSPHRASE` too, so the passphrase guards
only against an attacker who can read one secret but not the other — which
is not a threat that exists here.

What the passphrase *would* protect is the copy in the maintainer's local
keyring. If you want that, the right shape is a passphrase-protected
primary key with a separate unprotected signing subkey exported to CI,
rather than a passphrase that also has to be handed to the CI job.

### Who can sign

Anyone who can change a workflow in this repository can cause something to
be signed. That is the same set of people who can already change the source
that gets built, so it does not widen the trust boundary much — but it is
worth stating rather than leaving implicit.

If stronger separation is ever wanted, the upgrade path is a second key: a
release key kept offline for tagged releases, leaving this one for nightly
snapshots. `xymon-release` can ship both keys, so that change would not
break existing installations.

## Revocation certificate

GnuPG generated one automatically at key creation. It is stored as
`rpm-signing/xymon-rpm-signing.revocation.asc` in
[xymon-monitoring/private](https://github.com/xymon-monitoring/private),
and the original remains at
`~/.gnupg/openpgp-revocs.d/BD24FB87154D561B66F666DF639DE923AA08904A.rev`
on the generating machine.

This is the "cancel this key" statement, and it is what makes a compromised
key retirable. Note that it currently lives in the same place as the key it
revokes: an attacker who reaches `private` gets both. That is acceptable
here because reaching `private` already means being able to sign, so the
revocation certificate is not the weakest link — but a third copy held
outside GitHub would be a genuine improvement.

## If the key is compromised

1. Publish the revocation certificate above.
2. Generate a replacement (see below) and load it into `GPG_PRIVATE_KEY`.
3. Ship an `xymon-release` containing both the revocation and the new key,
   so existing installations learn about both.
4. Re-sign and re-publish the packages that should remain installable.

## Renewing before expiry

Expiry stops *new* signatures, not existing ones; packages already signed
stay valid.

```sh
gpg --edit-key "Xymon Project"
> expire            # choose a new period
> save
gpg --armor --export "Xymon Project" > RPM-GPG-KEY-xymon
```

Commit the refreshed public key. The fingerprint does not change, so
nothing on the user side has to be updated.

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
and EL8 is a supported target until 2029. Three years rather than never,
because a key that leaks and cannot expire is a problem forever.

Piping the export straight into `gh secret set` means the private key is
never written to a file or displayed.
