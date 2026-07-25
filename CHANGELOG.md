# Changelog

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
