# Releasing

There is no release automation. Tags are cut by hand, and the Homebrew formula
is updated by hand to match. This file is the process.

`Formula/git-trees.rb` in this repo is the **source of truth** for the formula,
but Homebrew never reads it from here. It takes effect only once it is copied
into the tap repo, [`brightdigit/homebrew-tap`](https://github.com/brightdigit/homebrew-tap),
which is what `brew tap brightdigit/tap` clones.

## 1. Cut and push the tag

Update `CHANGELOG.md` with the new version's `## What's Changed` section first,
then tag the release commit:

```bash
git tag -a v1.0.3 -m "v1.0.3"
git push origin v1.0.3
```

GitHub generates the source tarball for the tag automatically at
`https://github.com/brightdigit/git-trees/archive/refs/tags/v1.0.3.tar.gz`.

## 2. Compute the sha256 of the new tarball

Wait for the tag to appear on GitHub, then hash the tarball:

```bash
curl -fsSL https://github.com/brightdigit/git-trees/archive/refs/tags/v1.0.3.tar.gz \
  | shasum -a 256
```

`curl -f` makes a missing tag fail rather than hashing a 404 body — without it
you get a plausible-looking hash for the wrong bytes. If you want to be sure,
download to a file and check the contents:

```bash
curl -fsSL -o /tmp/git-trees.tar.gz \
  https://github.com/brightdigit/git-trees/archive/refs/tags/v1.0.3.tar.gz
tar tzf /tmp/git-trees.tar.gz     # should list git-trees, AGENTS.md.template, LICENSE
shasum -a 256 /tmp/git-trees.tar.gz
```

## 3. Bump the formula in this repo

Edit `Formula/git-trees.rb` and update both fields together — a stale `sha256`
against a new `url` fails every install with a checksum mismatch:

- `url` → the new tag's tarball
- `sha256` → the hash from step 2

Check it before committing:

```bash
ruby -c Formula/git-trees.rb
brew style Formula/git-trees.rb
```

Commit the bump to `main`.

## 4. Copy the formula into the tap

`brew audit` requires a formula that lives in a tap, so run it after copying:

```bash
git clone git@github.com:brightdigit/homebrew-tap.git
cp Formula/git-trees.rb homebrew-tap/Formula/git-trees.rb
cd homebrew-tap
brew audit --strict --formula brightdigit/tap/git-trees
git add Formula/git-trees.rb
git commit -m "git-trees 1.0.3"
git push
```

## 5. Verify with brew install

From a clean state, install through the tap the way a user would:

```bash
brew untap brightdigit/tap 2>/dev/null   # ensure a fresh clone
brew tap brightdigit/tap
brew install git-trees
git trees help
```

`git trees help` writes its usage to stderr and exits 0. Then leave the machine
as you found it if this was only a verification:

```bash
brew uninstall git-trees
```

## Follow-up: shell completions

Once shell completions ship (PR #51, targeted at v1.0.3), the completion files
are part of the release tarball and the formula's `install` block should install
them:

```ruby
bash_completion.install "completions/git-trees.bash"
zsh_completion.install "completions/_git-trees" => "_git-trees"
```

Add those lines only in the formula revision whose `url` points at a tag that
actually contains `completions/` — referencing files missing from the tarball
breaks `brew install` outright.
