# Package signing

Packages are signed so that `dnf` can verify they came from this project and
were not modified in transit. Without a signature a user has no way to tell a
real Xymon package from one someone else published.

The signing key is held by the project and used by CI. Everything below is
done **once**, by a maintainer, on their own machine.

## 1. Generate the key

```sh
gpg --full-generate-key
```

Answer the prompts:

| Prompt | Answer |
| --- | --- |
| kind of key | `RSA and RSA` (option 1) |
| keysize | `4096` |
| valid for | `3y` |
| Real name | `Xymon Project` |
| Email address | a project address, not a personal one |
| Comment | `RPM signing key` |

RSA rather than the more modern ed25519, because EL8's rpm predates
reliable EdDSA support and EL8 is a supported target until 2029.

Three years rather than never, because a key that leaks and cannot expire
is a problem forever. Renewing is one command and does not invalidate
already-signed packages.

Use a passphrase. CI needs it as a separate secret, so it is protecting
against someone reading the secret store, not against convenience.

## 2. Note the fingerprint

```sh
gpg --list-keys --fingerprint "Xymon Project"
```

Take the long hex string. It goes in this repository's README and in the
`xymon-release` package, so users can verify the key they fetched is the
key the project published. Publishing it in more than one place is the
point — a fingerprint that only lives on the same server as the packages
proves nothing.

## 3. Make a revocation certificate, before you need it

```sh
gpg --output xymon-revoke.asc --gen-revoke "Xymon Project"
```

This is the "cancel this key" statement. Generate it now, while the key is
healthy, and store it somewhere **other than GitHub** — if the key is
compromised because GitHub was, the revocation certificate must not be in
the same place. A maintainer's password manager or an offline copy is fine.

Without it, a leaked key cannot be cleanly retired.

## 4. Export the two halves

```sh
# Public half: commit this to the repository.
gpg --armor --export "Xymon Project" > RPM-GPG-KEY-xymon

# Private half: this is the secret. Do not commit it.
gpg --armor --export-secret-keys "Xymon Project" > private.asc
```

## 5. Load the private half into CI

In this repository: **Settings → Secrets and variables → Actions → New
repository secret**.

| Secret name | Contents |
| --- | --- |
| `GPG_PRIVATE_KEY` | the entire contents of `private.asc`, including the `-----BEGIN`/`-----END` lines |
| `GPG_PASSPHRASE` | the passphrase chosen in step 1 |

GitHub encrypts both. They can be replaced or deleted but never read back
out, and they are not exposed to workflow runs from forks.

Then delete the local copy:

```sh
rm private.asc
```

The key itself remains in your GnuPG keyring; only the exported file goes.

## 6. Commit the public half

```sh
git add RPM-GPG-KEY-xymon
git commit -m "Add the RPM signing public key"
```

Publishing starts working on the next build.

## What CI does with it

The publish job imports the private key, signs each RPM with
`rpm --addsign`, and signs the repository metadata (`repomd.xml`) so that
the package *list* is verifiable too, not only the packages. Both
`gpgcheck` and `repo_gpgcheck` are enabled in the shipped `.repo` file.

## Who can sign

Anyone able to change a workflow in this repository can cause something to
be signed. That is the same set of people who can already change the source
that gets built, so it does not widen the trust boundary much — but it is
worth being explicit about.

If the project later wants a stronger separation, the upgrade path is to
add a second key: a release key kept offline for tagged releases, leaving
this one for nightly snapshots. `xymon-release` can ship both keys, so that
change does not break existing installations.

## If the key is compromised

1. Publish the revocation certificate from step 3.
2. Generate a new key and repeat this document.
3. Ship a new `xymon-release` containing both the revocation and the new
   key, so existing installations learn about both.
4. Re-sign and re-publish the packages that should remain installable.

## Renewing before expiry

```sh
gpg --edit-key "Xymon Project"
> expire          # choose a new period
> save
gpg --armor --export "Xymon Project" > RPM-GPG-KEY-xymon
```

Commit the refreshed public key. Packages signed under the old expiry stay
valid; expiry stops *new* signatures, not old ones.
