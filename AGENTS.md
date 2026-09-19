# AGENTS.md — orientation for AI agents working on mob_location

You're in **mob_location**, a Mob plugin for device location — GPS + network fixes, one-shot (`get_once`) or continuous (`start` / `stop`). iOS uses `CLLocationManager`; Android uses `FusedLocationProviderClient` via the plugin-owned `io.mob.location.MobLocationBridge` Kotlin bridge. Updates arrive on the caller's process inbox as `{:location, %{lat:, lon:, accuracy:, altitude:}}` or `{:location, :error, reason}`.

**Also read [`~/code/mob/AGENTS.md`](../mob/AGENTS.md)** for the system view — mob's three-repo topology, plugin manifest schema, `Mob.Composite` / `Mob.Sigil`, how to drive a running app from your session, and the cross-cutting pre-empt-failure rules. This file is mob_location-specific.

> **Keep this file current.** When you change the delivery shape, add an option to `start/2`, or hit a gotcha that would trip the next agent, fix it here in the same commit — not in a follow-up.

## What mob_location is, in one paragraph

A cross-platform capability plugin with one Elixir surface (`MobLocation`), one Erlang NIF module (`:mob_location_nif`), and two native implementations under `priv/native/`. Kevin extracted it from mob core in the Wave-2 plugin split. The Elixir API is three functions — `get_once/1`, `start/2`, `stop/1` — all of which invoke the NIF and return the socket unchanged; results flow back asynchronously as `handle_info` messages so the screen never blocks on a fix. The `:location` runtime permission is owned by this plugin: the iOS NIF self-registers a `mob_location_request_permission` handler at load, and the Android bridge implements `MobPermissionProvider` to supply the `:location` → `ACCESS_FINE_LOCATION` mapping. `Mob.Permissions.request(socket, :location)` routes through core into whichever side is live.

## What mob_location is NOT

* **Not [mob_background](https://hexdocs.pm/mob_background).** Location updates can nudge iOS / Android to run our process, but keeping the BEAM alive while the user is on another screen or the app is backgrounded is `mob_background`'s job (silent-audio session on iOS, foreground service on Android). mob_location does not guarantee delivery while the app is backgrounded — if you need that, compose with `mob_background`.
* **Not [mob_bluetooth](https://hexdocs.pm/mob_bluetooth).** BLE beacons / proximity-based indoor positioning are a Bluetooth problem, not a GPS/network one. If you're trying to detect "is the user near this beacon?" that lives in `mob_bluetooth`, not here.
* **Not a background-fetch scheduler.** The `:balanced` / `:high` / `:low` knob on `start/2` is a foreground accuracy hint, not a wake schedule. OS-triggered background execution lives in [mob_wake](https://hexdocs.pm/mob_wake).

## Anatomy of the plugin

* `lib/mob_location.ex` — public API + reference for the `handle_info` shapes. Any change to message shape must land here first (moduledoc is what users read).
* `lib/mob_location/demo_screen.ex` — `MobLocation.DemoScreen`, a `use Mob.Screen` that ships in the manifest's `:screens`. Auto-listable from a generated host's home. Real apps delete both the screen and the manifest entry.
* `src/mob_location_nif.erl` — the NIF stub module. Exports `location_get_once/0`, `location_start/1`, `location_stop/0`. `on_load` tolerates load failure so the host (Elixir-only, no native linked) falls back to `nif_not_loaded` at call time instead of crashing at boot.
* `priv/mob_plugin.exs` — the manifest. Declares one `:screens` entry, two `:nifs` entries (same module name, `platform: :ios` + `platform: :android`), the `:location` capability with its iOS handler, and the Android bridge / gradle dep + iOS framework / plist key.
* `priv/native/ios/mob_location_nif.m` — Objective-C, `-fobjc-arc`, `CLLocationManager`. Registers the `:location` permission handler at NIF load via `mob_register_permission_handler` (a core symbol linked into the same static binary). Delivers via raw `enif_send` because core's `mob_send3` isn't exported to plugins.
* `priv/native/jni/mob_location_nif.zig` — Zig, imports core's `erts` + `jni` modules, exports the `Java_io_mob_location_MobLocationBridge_*` C-ABI symbols directly (no separate `jni_source` C file). Method-id cache is populated from `nativeRegister` at bridge init.
* `priv/native/android/MobLocationBridge.kt` — Kotlin, `object MobLocationBridge : MobActivityAware, MobPermissionProvider`. Wraps `FusedLocationProviderClient`. mob_dev's plugin bootstrap generator wires `register()` + `setActivity(...)` into the host's `MobPluginBootstrap.registerAll()`.
* `test/mob_location_test.exs` — manifest validation (via the real `MobDev.Plugin.{Manifest, Validator}`), NIF-stub arity checks, and public-API surface tests.

No `decisions/` directory yet — if you make a non-obvious tradeoff (a delivery-shape change, an accuracy default flip, a permission-flow rework), add one in the same commit.

## Cross-repo work

**mob (framework):** owns `Mob.Permissions.request/2` and the two extern symbols this plugin depends on: `mob_register_permission_handler` (iOS) and `get_jenv` / `g_jvm` (Android). If you rename or re-export either side, the plugin's NIF will link-fail on the host binary — coordinate the change across both repos in one PR pair.

**mob_dev:** owns the native build path that merges this plugin's `plist_keys`, gradle deps, Android manifest permissions, and the Kotlin bridge into the host app. The `mix mob.deploy --native` step is what exercises the .m / .zig / .kt sources — none of them are compiled by `mix test`.

**mob_new / mob_plugin_demo:** `mob_plugin_demo` is the host app of record for kicking the tires. Add mob_location as a path dep, `mix mob.deploy --native` to a device, navigate to `/mob_location/demo`, run all three buttons through the permission grant + deny paths.

## Testing

Elixir suite:

```bash
mix setup       # deps.get + activate .githooks
mix test
```

The suite validates the manifest against the real pre-publish validator and asserts NIF-stub arity — it does NOT exercise the native paths. Native changes need a `mix mob.deploy --native` of a host app (mob_plugin_demo is the canonical target) and a device check before the commit lands.

## The pre-empt-failure rules that matter here

1. **Permissions gate everything.** `MobLocation.get_once/1` and `start/2` will silently do nothing if `:location` isn't granted first. The demo screen shows the pattern: call `Mob.Permissions.request(socket, :location)`, stash what you meant to do in `assigns.pending`, then dispatch on `{:permission, :location, :granted | :denied}`. Any docs example that skips the permission call is wrong.
2. **iOS ships "when in use" only.** The manifest declares `NSLocationWhenInUseUsageDescription`, not `NSLocationAlwaysAndWhenInUseUsageDescription`. Foreground fixes work; backgrounded / suspended-app fixes do not. If you need "always" behaviour, that is a manifest change, an Apple review-team conversation, and a `mob_background` composition — not a one-line plist edit.
3. **Android background location is a separate permission.** `ACCESS_FINE_LOCATION` + `ACCESS_COARSE_LOCATION` in the manifest cover foreground use. `ACCESS_BACKGROUND_LOCATION` is a distinct runtime permission on Android 10+, requested separately and gated by Play policy. This plugin does not request it — same reasoning as iOS "always."
4. **Coarse-only grants are valid.** MOB-75 accepts coarse-only grants on Android: users can toggle "precise" off in the system dialog and still get fixes. Don't add code that treats coarse-only as a denial — you will regress that fix.
5. **Continuous updates burn battery.** `start/2` runs `FusedLocationProviderClient` / `CLLocationManager` at the requested accuracy until `stop/1`. Call `stop/1` from `terminate/2`, on tab-away, on a "pause" tap — anywhere you no longer need fixes. `:high` accuracy on both platforms wakes the GPS chip; `:balanced` mixes cell / wifi and is what most apps want.
6. **Accuracy vs battery is user-visible.** Default is `:balanced`. Only reach for `:high` when the user asked for a map pin or a navigation update; `:low` when a city-level fix is enough. A screen that leaves `:high` running in the background is what will land the app on the OS's battery-usage shame list.
7. **`{:location, :error, reason}` is not `{:error, reason}`.** The three-tuple shape is deliberate: it keeps error deliveries out of the same handler that owns fix data. `reason` is `:permission_denied` (denied or revoked mid-session) or `:unavailable` (OS can't get a fix right now). Add new reasons as atoms; don't smuggle strings.
8. **Host builds have no NIF linked.** The `.erl` stub tolerates NIF load failure so a plain `mix test` on the host doesn't crash. Any code that assumes the NIF is loaded (e.g. calling `:mob_location_nif.location_stop()` from a non-device test) must guard for `nif_not_loaded` or run only on a device.

## Pre-commit checklist

```bash
mix test                # full suite
mix format
mix credo --strict      # includes ExSlop + jump_credo_checks
```

The pre-push hook (`.githooks/pre-push`, activated via `mix setup` or `git config core.hooksPath .githooks`) runs format / credo / compile on every push, and the full test suite when `mix.exs` changes (release preflight).

Native changes (`.m` / `.zig` / `.kt`) aren't exercised by `mix test` — they need a `mix mob.deploy --native` of a host app and a device check before committing.

## Release

`@version` in `mix.exs` on master triggers `.github/workflows/release.yml` (tag + GitHub Release + Hex publish, each step idempotent). The workflow also verifies the CI signing key matches `priv/mob_plugin.pub` before publishing. Canonical release process lives at [`~/code/mob/RELEASE.md`](../mob/RELEASE.md); do NOT bump the version without explicit permission.
