# Releasing

There is no release automation for cutting tags — those are still done by hand.
Once a GitHub release is published, `.github/workflows/homebrew-tap.yml` bumps
the formula and pushes it to the tap via the
[`homebrew-tap/`](../homebrew-tap) [git subrepo](https://github.com/ingydotnet/git-subrepo).

`homebrew-tap/Formula/git-trees.rb` in this repo is the **source of truth** for
the formula. Homebrew installs it from
[`brightdigit/homebrew-tap`](https://github.com/brightdigit/homebrew-tap), which
is what `brew tap brightdigit/tap` clones.

## One-time setup

### 1. Embed the tap as a subrepo

From a commit that already contains `homebrew-tap/Formula/git-trees.rb`:

```bash
git subrepo init homebrew-tap \
  -r https://github.com/brightdigit/homebrew-tap.git \
  -b main
git subrepo push homebrew-tap
```

`init` records `homebrew-tap/.gitrepo`; `push` populates the (possibly empty)
tap remote. Requires push access to `brightdigit/homebrew-tap`.

### 2. Repository secret

Add a `HOMEBREW_TAP_TOKEN` secret on `brightdigit/git-trees`: a classic PAT or
fine-grained token with `contents: write` on both `brightdigit/git-trees` and
`brightdigit/homebrew-tap`. The workflow uses it to commit the formula bump here
and to `git subrepo push` the tap.

## Cut a release

Update `CHANGELOG.md` with the new version's `## What's Changed` section, then:

```bash
git tag -a v1.0.3 -m "v1.0.3"
git push origin v1.0.3
```

Create the GitHub release for that tag (or publish from the tag). The
`Homebrew tap` workflow then:

1. Downloads `https://github.com/brightdigit/git-trees/archive/refs/tags/v1.0.3.tar.gz`
2. Rewrites `url` / `sha256` in `homebrew-tap/Formula/git-trees.rb`
3. Commits and pushes that bump to this repo
4. Runs `git subrepo push homebrew-tap`

To re-run for an existing tag: **Actions → Homebrew tap → Run workflow** and
pass the tag (e.g. `v1.0.3`).

## Manual fallback

If the workflow cannot run, bump and push by hand:

```bash
tag=v1.0.3
url="https://github.com/brightdigit/git-trees/archive/refs/tags/${tag}.tar.gz"
sha=$(curl -fsSL "$url" | shasum -a 256 | awk '{ print $1 }')

# edit homebrew-tap/Formula/git-trees.rb — set url and sha256 together
ruby -c homebrew-tap/Formula/git-trees.rb
brew style homebrew-tap/Formula/git-trees.rb

# optional: audit requires the formula to live in a tap checkout
git subrepo push homebrew-tap
brew untap brightdigit/tap 2>/dev/null
brew tap brightdigit/tap
brew audit --strict --formula brightdigit/tap/git-trees
```

## Verify with brew install

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
