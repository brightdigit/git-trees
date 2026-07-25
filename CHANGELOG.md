# Changelog

## v1.0.0

First release of `git-trees`: a `git` subcommand for managing a bare-repo +
worktrees layout. Pure git — no `gh`, no `jq`, no forge integration.

## What's Changed

* Seed `AGENTS.md` at the container root only, not in each worktree
* Document that `add` writes to the remote, and add `--no-push`
* Support slash branch names via slugged worktree directories (`feature/x` → `feature-x/`)
* Harden `add`: clear collision errors and fail when track/push fails
* Document env var setup; verify placeholder URLs resolved
* Docs: a quickstart that works, a concepts primer, and honest install docs
* CI: run smoke tests on Linux and macOS
