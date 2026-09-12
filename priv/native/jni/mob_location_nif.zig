//! mob_location_nif — Android location tier-1 ZIG plugin NIF.
//!
//! Extracted from mob-core's `mob_nif.zig`: nif_location_get_once/start/stop +
//! the mob_deliver_location term builder. The Kotlin side is the plugin-owned
//! bridge class `io.mob.location.MobLocationBridge` (FusedLocationProviderClient);
//! its single inbound delivery thunk is exported directly from this zig file
//! (no separate jni_source C needed — zig emits the C-ABI Java_ symbol).
//!
//! Build path: compiled via `addZigObject` from `-Dplugin_zig_nifs`, reaching
//! mob-core ERTS / JNI bindings through `@import("erts")` / `@import("jni")`.
//! `get_jenv` + `g_jvm` are mob-core exports linked into the same `.so`.
//!
//! Bridge-class registration: the JVM calls
//! `Java_io_mob_location_MobLocationBridge_nativeRegister(jenv, cls)` at startup
//! (generated MobPluginBootstrap.registerAll -> register()); that thunk caches a
//! global ref to the bridge jclass + the 3 location method IDs.
const std = @import("std");
const erts = @import("erts");
const jni = @import("jni");

// mob-core exports (linked into the same .so). NOT duplicated.
extern fn get_jenv(attached: *c_int) ?*jni.JNIEnv;
extern var g_jvm: ?*jni.JavaVM;

// ── Plugin-owned bridge-class method-id cache ────────────────────────────
const LocMethods = struct {
    get_once: jni.JMethodID = null,
    start: jni.JMethodID = null,
    stop: jni.JMethodID = null,
};

var g_loc: LocMethods = .{};
var g_loc_cls: jni.JClass = null;

// ── nativeRegister thunk — cache the bridge jclass + method ids ───────────
// A missing method leaves a `NoSuchMethodError` pending on the JNIEnv;
// `cacheMethod` clears it so subsequent lookups aren't shadowed by a stale
// pending exception. See MOB-77.
inline fn cacheMethod(
    jenv: *jni.JNIEnv,
    cls: jni.JClass,
    name: [*:0]const u8,
    sig: [*:0]const u8,
) jni.JMethodID {
    const m = jni.getStaticMethodID(jenv, cls, name, sig);
    if (m == null) jni.exceptionClear(jenv);
    return m;
}

export fn Java_io_mob_location_MobLocationBridge_nativeRegister(jenv: *jni.JNIEnv, cls: jni.JClass) callconv(.c) void {
    g_loc_cls = jni.newGlobalRef(jenv, cls);
    if (g_loc_cls == null) return;
    g_loc.get_once = cacheMethod(jenv, cls, "location_get_once", "(JLjava/lang/String;)V");
    g_loc.start = cacheMethod(jenv, cls, "location_start", "(JLjava/lang/String;)V");
    g_loc.stop = cacheMethod(jenv, cls, "location_stop", "()V");
}

// ── Thread-attach + pid round-trip helpers (mirror mob-core / bt) ─────────
inline fn detachIfAttached(attached: c_int) void {
    if (attached != 0) {
        if (g_jvm) |jvm| jni.detachCurrentThread(jvm);
    }
}

inline fn pidToJlong(pid: erts.ErlNifPid) jni.JLong {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return @bitCast(pid.pid);
    }
    return @intCast(pid.pid);
}

inline fn pidFromLong(jpid: jni.JLong) erts.ErlNifPid {
    if (@sizeOf(erts.ERL_NIF_TERM) == @sizeOf(jni.JLong)) {
        return .{ .pid = @bitCast(jpid) };
    }
    const low: u32 = @truncate(@as(u64, @bitCast(jpid)));
    return .{ .pid = low };
}

/// Call `MobLocationBridge.<method>(pid_long, arg)` — async; the fix lands later
/// via the nativeDeliverLocation thunk. Returns :ok unconditionally.
fn callBridgePidStr(env: ?*erts.ErlNifEnv, method: jni.JMethodID, pid: erts.ErlNifPid, arg: ?[*:0]const u8) erts.ERL_NIF_TERM {
    if (g_loc_cls == null or method == null) return erts.ok(env);
    var attached: c_int = 0;
    const jenv = get_jenv(&attached) orelse return erts.ok(env);
    const jarg: jni.JString = if (arg) |a| jni.newStringUTF(jenv, a) else null;
    jenv.*.CallStaticVoidMethod.?(jenv, g_loc_cls, method, pidToJlong(pid), jarg);
    // Kotlin bridge methods can throw SecurityException on missing
    // ACCESS_FINE_LOCATION/ACCESS_COARSE_LOCATION grants. MOB-77: clear here so
    // a pending exception cannot leak to the next JNI call on this thread.
    jni.exceptionClear(jenv);
    if (jarg != null) jni.deleteLocalRef(jenv, jarg);
    detachIfAttached(attached);
    return erts.ok(env);
}

// ── Inbound delivery thunk — Kotlin's location callback calls this ────────
// Builds {:location, %{lat, lon, accuracy, altitude}} and sends it to the
// waiting pid. Exported directly (zig emits the Java_ C-ABI symbol).
export fn Java_io_mob_location_MobLocationBridge_nativeDeliverLocation(jenv: *jni.JNIEnv, cls: jni.JClass, pid_long: jni.JLong, lat: f64, lon: f64, acc: f64, alt: f64) callconv(.c) void {
    _ = jenv;
    _ = cls;
    var pid = pidFromLong(pid_long);
    const env = erts.enif_alloc_env() orelse return;
    defer erts.enif_free_env(env);
    const keys = [_]erts.ERL_NIF_TERM{
        erts.atom(env, "lat"),
        erts.atom(env, "lon"),
        erts.atom(env, "accuracy"),
        erts.atom(env, "altitude"),
    };
    const vals = [_]erts.ERL_NIF_TERM{
        erts.enif_make_double(env, lat),
        erts.enif_make_double(env, lon),
        erts.enif_make_double(env, acc),
        erts.enif_make_double(env, alt),
    };
    const map = erts.makeMap(env, &keys, &vals) orelse return;
    const msg = erts.makeTuple(env, .{ erts.atom(env, "location"), map });
    _ = erts.enif_send(null, &pid, env, msg);
}

// Error delivery — Kotlin passes a small code instead of a string so no JNI
// string read is needed: 0 = permission_denied, anything else = unavailable.
// Builds {:location, :error, reason}.
export fn Java_io_mob_location_MobLocationBridge_nativeDeliverLocationError(jenv: *jni.JNIEnv, cls: jni.JClass, pid_long: jni.JLong, code: c_int) callconv(.c) void {
    _ = jenv;
    _ = cls;
    var pid = pidFromLong(pid_long);
    const env = erts.enif_alloc_env() orelse return;
    defer erts.enif_free_env(env);
    const reason = if (code == 0) erts.atom(env, "permission_denied") else erts.atom(env, "unavailable");
    const msg = erts.makeTuple(env, .{ erts.atom(env, "location"), erts.atom(env, "error"), reason });
    _ = erts.enif_send(null, &pid, env, msg);
}

// ── NIFs ──────────────────────────────────────────────────────────────────
fn nif_location_get_once(
    env: ?*erts.ErlNifEnv,
    argc: c_int,
    argv: [*]const erts.ERL_NIF_TERM,
) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    var pid: erts.ErlNifPid = undefined;
    _ = erts.enif_self(env, &pid);
    return callBridgePidStr(env, g_loc.get_once, pid, "balanced");
}

fn nif_location_start(
    env: ?*erts.ErlNifEnv,
    argc: c_int,
    argv: [*]const erts.ERL_NIF_TERM,
) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    var acc_buf: [16]u8 = @splat(0);
    jni.copyZ(&acc_buf, "balanced");
    _ = erts.enif_get_atom(env, argv[0], &acc_buf, acc_buf.len, erts.ERL_NIF_LATIN1);
    var pid: erts.ErlNifPid = undefined;
    _ = erts.enif_self(env, &pid);
    return callBridgePidStr(env, g_loc.start, pid, jni.asCStr(&acc_buf));
}

fn nif_location_stop(
    env: ?*erts.ErlNifEnv,
    argc: c_int,
    argv: [*]const erts.ERL_NIF_TERM,
) callconv(.c) erts.ERL_NIF_TERM {
    _ = argc;
    _ = argv;
    if (g_loc_cls == null or g_loc.stop == null) return erts.ok(env);
    var attached: c_int = 0;
    const jenv = get_jenv(&attached) orelse return erts.ok(env);
    jenv.*.CallStaticVoidMethod.?(jenv, g_loc_cls, g_loc.stop);
    jni.exceptionClear(jenv);
    detachIfAttached(attached);
    return erts.ok(env);
}

// ── NIF table + init entry point ─────────────────────────────────────────
fn nifLoad(env: ?*erts.ErlNifEnv, priv: *?*anyopaque, info: erts.ERL_NIF_TERM) callconv(.c) c_int {
    _ = env;
    _ = priv;
    _ = info;
    return 0;
}

const nif_funcs = [_]erts.ErlNifFunc{
    .{ .name = "location_get_once", .arity = 0, .fptr = nif_location_get_once, .flags = 0 },
    .{ .name = "location_start", .arity = 1, .fptr = nif_location_start, .flags = 0 },
    .{ .name = "location_stop", .arity = 0, .fptr = nif_location_stop, .flags = 0 },
};

var nif_entry: erts.ErlNifEntry = .{
    .major = erts.ERL_NIF_MAJOR_VERSION,
    .minor = erts.ERL_NIF_MINOR_VERSION,
    .name = "mob_location_nif",
    .num_of_funcs = nif_funcs.len,
    .funcs = &nif_funcs,
    .load = nifLoad,
    .reload = null,
    .upgrade = null,
    .unload = null,
    .vm_variant = erts.ERL_NIF_VM_VARIANT,
    .options = 1,
    .sizeof_ErlNifResourceTypeInit = erts.SIZEOF_ErlNifResourceTypeInit,
    .min_erts = erts.ERL_NIF_MIN_ERTS_VERSION,
};

pub export fn mob_location_nif_nif_init() callconv(.c) *erts.ErlNifEntry {
    return &nif_entry;
}
