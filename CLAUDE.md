# mob_location — Agent Instructions

**Read [`AGENTS.md`](AGENTS.md) first**, then [`~/code/mob/AGENTS.md`](../mob/AGENTS.md) for the system view. Together they cover the plugin anatomy, the permission/battery/accuracy pre-empt-failure rules, and the cross-repo work with mob / mob_dev / mob_plugin_demo. This file goes deeper on Claude Code-specific workflow detail.

> **Keep AGENTS.md up to date** when you change the delivery shape, add a `start/2` option, or hit a new gotcha. Out-of-date guidance there causes wrong decisions downstream — fix it in the same commit, not in a follow-up.

## Worktrees

**Default assumption: work happens in a git worktree.** Kevin runs multiple agents in parallel; each task in its own worktree prevents conflicts.

If a task is assigned to you and worktree usage isn't mentioned, ask whether one is wanted. Yes for anything non-trivial or that touches native code. In-place is fine for a single-file doc edit, one-line config change, or a version bump.

The git stash stack is shared across worktrees — never bare `git stash` / `git stash pop`.

## Pre-commit checklist

See AGENTS.md. Run all in this order:

```bash
mix test
mix format
mix credo --strict
```

The pre-push hook adds format / credo / compile on every push and full tests when `mix.exs` changes.

### Tests are part of the change

New behaviour ships with a test unless the change is small enough that a test would only restate it. The bar is: **would this test fail if the fix were reverted?** Check by reverting it.

For mob_location specifically:

* Any change to `{:location, ...}` delivery shape needs a test that pins the shape (a screen-level integration is fine — the NIF isn't callable in host tests).
* Manifest changes (new `plist_keys`, gradle deps, permissions) need a `Validator.validate_plugin/2` assertion — the existing manifest test suite is where these belong.
* Coarse-only grant handling on Android (MOB-75) is a permanent invariant — don't add code that treats coarse-only as a denial.

### Adversarial review — before every non-trivial commit

Spawn a subagent, point it at the diff, tell it to find defects rather than approve. Especially for this plugin:

* **Permission-flow regressions.** The demo screen's `pending`-then-dispatch-on-grant pattern is the contract. A change that lets `start/2` run before `Mob.Permissions.request/2` has resolved is a silent-do-nothing bug.
* **Battery-cost regressions.** Anything that defaults `start/2` to `:high` accuracy, or that fails to `stop/1` on screen exit, is a battery bug users won't report but WILL rate the app poorly for.
* **`stop/1` idempotency.** Users tap Stop twice, apps call `stop/1` in both `terminate/2` and a nav handler. The NIF must tolerate that.
* **NIF-not-loaded fallback.** The host build has no native linked. Any code path reachable from `mix test` that assumes the NIF is loaded will crash CI.

Skip only for: formatting, a typo, a version bump, a changelog edit.

## Release flow

Canonical process in [`~/code/mob/RELEASE.md`](../mob/RELEASE.md). mob_location specifics:

* `@version` in `mix.exs` is the trigger. Push it to master; `.github/workflows/release.yml` handles tag / GH-release / hex-publish, each step idempotent. The workflow verifies the CI signing key matches `priv/mob_plugin.pub` before publishing.
* The `mob` floor pin in `mix.exs` is load-bearing. Do not bump it if the plugin uses a new mob feature that hasn't shipped yet.
* **Never ship without physical-device verification.** Simulators lie for this plugin — iOS simulator location is a fake feed set from the Xcode menu; Android emulator location is `adb emu geo fix`. Neither exercises real GPS acquisition, real permission dialogs, or coarse-vs-fine grant handling. Kevin has a Moto G Power 5G 2024 and an iPhone SE for device verification.
