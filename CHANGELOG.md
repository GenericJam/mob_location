# Changelog

All notable changes to **mob_location** are documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versioning: [SemVer](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Fixed

- **Android: JNI exception no longer leaks onto the BEAM scheduler thread**
  (MOB-77). The zig NIF had zero `ExceptionCheck`/`ExceptionClear` calls,
  and the runtime NIFs didn't guard on a missing bridge cache — a
  `SecurityException` from a missing `ACCESS_FINE_LOCATION`/
  `ACCESS_COARSE_LOCATION` grant, or a `NoSuchMethodError` from an
  older/stripped bridge, would linger on the JNIEnv. The next JNI call on
  the same BEAM scheduler thread was then undefined behaviour per the JNI
  spec, and a null bridge cache passed a null `jclass` into
  `CallStaticVoidMethod` (also UB).

  Fix: introduce a `cacheMethod` helper for `nativeRegister` (same shape as
  the recent mob_bluetooth/mob_background fixes); guard `g_loc_cls == null`
  and `<method> == null` in the runtime NIFs (silent `:ok` — matches the
  moduledoc's documented failure mode where a missing plist key / manifest
  entry silently does nothing); `jni.exceptionClear(jenv)` after both
  `CallStaticVoidMethod` sites (helper `callBridgePidStr` covers
  `get_once` and `start`; `nif_location_stop` calls directly).

  Return-type contracts are unchanged (`MobLocation.get_once/1`,
  `start/2`, `stop/1` all return `socket`). iOS path is untouched.

---

## [0.1.3] - 2026-06-16

### Changed
- Signed release: the published package now carries a verified Ed25519
  signature (shared mob first-party key, regenerated in CI on every
  release). Generated apps trust it via `config :mob, :trusted_plugins`,
  so it clears the plugin signature gate without `acknowledge_unsafe_plugins`.

## [0.1.2] - 2026-06-15

### Fixed
- Removed a stale `priv/mob_plugin.sig` / `mob_plugin.pub` that shipped in 0.1.1.
  It was signed before the 0.1.1 manifest gained `:screens`, so the signature no
  longer matched the manifest and the plugin signature gate hard-failed
  (`invalid_signature`, not bypassable by `acknowledge_unsafe_plugins`). Now
  unsigned, consistent with the other first-party capability plugins.

## [0.1.1] - 2026-06-15

### Added
- Bundled `MobLocation.DemoScreen` — a ready-to-run sample (get-once / start / stop, live coords) declared in the manifest's `:screens`, so a generated app can kick the tires on activation. It's pure-Elixir and hot-pushable; the plugin is now tier 3 (NIF + screens). Delete the screen + its `:screens` entry in a real app.

## [0.1.0] - 2026-06-12

Initial release. Device location (GPS / network) for Mob apps.

- `MobLocation.start/2` / `stop/1` with updates delivered via `handle_info`.
- Extracted from mob core in the 0.7.0 plugin-extraction wave.
- Requires `mob ~> 0.7`.
