# Changelog

## v1.0.3

## What's Changed

* Add `sync` subcommand for fetching and updating worktrees by @leogdion in https://github.com/brightdigit/git-trees/issues/50
* Add `prune` subcommand for clearing stale worktree metadata by @leogdion in https://github.com/brightdigit/git-trees/issues/55
* Add bash and zsh completions by @leogdion in https://github.com/brightdigit/git-trees/issues/51
* Add a one-line curl install by @leogdion in https://github.com/brightdigit/git-trees/issues/54
* Fix `add` creating the base branch instead of the requested one when the base exists only on the remote by @leogdion in https://github.com/brightdigit/git-trees/issues/61
* Add Homebrew formula and release automation by @leogdion in https://github.com/brightdigit/git-trees/issues/49

**Full Changelog**: https://github.com/brightdigit/git-trees/compare/v1.0.2...v1.0.3

## v1.0.2

## What's Changed

* Introduce `rm` and `clean` subcommands by @leogdion in https://github.com/brightdigit/git-trees/pull/47
* Adding logo for git-trees by @leogdion in https://github.com/brightdigit/git-trees/pull/52

**Full Changelog**: https://github.com/brightdigit/git-trees/compare/v1.0.1...v1.0.2

## v1.0.1

## What's Changed

* Install the agents template on curl and warn when missing by @leogdion in https://github.com/brightdigit/git-trees/pull/46
* Pin the curl install to `main` as the stable release

**Full Changelog**: https://github.com/brightdigit/git-trees/compare/v1.0.0...v1.0.1

## v1.0.0

First release of `git-trees`: a `git` subcommand for managing a bare-repo +
worktrees layout. Pure git — no `gh`, no `jq`, no forge integration.

## What's Changed

* Seed `AGENTS.md` at the container root only, not in each worktree by @leogdion in https://github.com/brightdigit/git-trees/pull/16
* Document that `add` writes to the remote, and add `--no-push` by @leogdion in https://github.com/brightdigit/git-trees/pull/37
* Support slash branch names via slugged worktree directories (`feature/x` → `feature-x/`) by @leogdion in https://github.com/brightdigit/git-trees/pull/36
* Harden `add`: clear collision errors and fail when track/push fails by @leogdion in https://github.com/brightdigit/git-trees/pull/10
* Document env var setup; verify placeholder URLs resolved by @leogdion in https://github.com/brightdigit/git-trees/pull/15
* Docs: a quickstart that works, a concepts primer, and honest install docs by @leogdion in https://github.com/brightdigit/git-trees/pull/38
* CI: run smoke tests on Linux and macOS by @leogdion in https://github.com/brightdigit/git-trees/pull/11

**Full Changelog**: https://github.com/brightdigit/git-trees/commits/v1.0.0
