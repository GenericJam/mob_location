/* mob_location_nif — iOS location tier-1 plugin NIF (Objective-C).
 *
 * Extracted from mob-core's ios/mob_nif.m: the CLLocationManager location
 * updates (location_get_once/start/stop + MobLocationPluginDelegate) and the
 * :location permission flow (MobLocationPluginPermissionDelegate +
 * request_location_permission). Registered as the Erlang module
 * mob_location_nif via ERL_NIF_INIT; compiled as ObjC (-fobjc-arc) by the
 * plugin C-NIF path because the manifest entry is lang: :objc.
 *
 * The NIF's load callback registers the :location permission handler with
 * core's runtime permission registry (mob_register_permission_handler, an
 * exported core symbol linked into the same static binary), so
 * Mob.Permissions.request(socket, :location) falls through core to it. Unlike
 * core's version, the permission result is delivered via raw enif_send (core's
 * mob_send3 is a private static, not linkable from the plugin).
 */
#import <CoreLocation/CoreLocation.h>
#import <Foundation/Foundation.h>
#include <erl_nif.h>

/* Defined in core mob's ios/mob_nif.m, linked into the same static binary. */
extern void mob_register_permission_handler(const char *cap, void (*fn)(ErlNifPid));

// ── {:permission, :location, status} delivery (raw enif) ──────────────────
static void send_permission(ErlNifPid pid, const char *status) {
  ErlNifEnv *env = enif_alloc_env();
  ERL_NIF_TERM msg = enif_make_tuple3(env, enif_make_atom(env, "permission"),
                                      enif_make_atom(env, "location"), enif_make_atom(env, status));
  enif_send(NULL, &pid, env, msg);
  enif_free_env(env);
}

// ── Permission delegate ───────────────────────────────────────────────────
@interface MobLocationPluginPermissionDelegate : NSObject <CLLocationManagerDelegate>
@property(nonatomic) ErlNifPid pid;
@property(nonatomic) BOOL resolved;
@end

static MobLocationPluginPermissionDelegate *g_permission_delegate = nil;
static CLLocationManager *g_permission_manager = nil;

@implementation MobLocationPluginPermissionDelegate
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)manager {
  CLAuthorizationStatus status = manager.authorizationStatus;
  if (status == kCLAuthorizationStatusNotDetermined) {
    // Dialog still on screen / OS hasn't picked an initial state.
    return;
  }
  self.resolved = YES;
  ErlNifPid p = self.pid;
  BOOL granted = (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
                  status == kCLAuthorizationStatusAuthorizedAlways);
  send_permission(p, granted ? "granted" : "denied");
}
@end

static void request_location_permission(ErlNifPid pid) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_permission_manager) {
      g_permission_manager = [[CLLocationManager alloc] init];
    }
    g_permission_delegate = [[MobLocationPluginPermissionDelegate alloc] init];
    g_permission_delegate.pid = pid;
    g_permission_manager.delegate = g_permission_delegate;
    // requestWhenInUseAuthorization is idempotent — already-granted permissions
    // short-circuit and the delegate fires immediately.
    [g_permission_manager requestWhenInUseAuthorization];
  });
}

// The handler registered with core's permission registry for :location.
static void mob_location_request_permission(ErlNifPid pid) { request_location_permission(pid); }

// ── Location-updates delegate ─────────────────────────────────────────────
@interface MobLocationPluginDelegate : NSObject <CLLocationManagerDelegate>
@property(nonatomic) ErlNifPid pid;
@property(nonatomic) BOOL oneShot;
@end

static MobLocationPluginDelegate *g_location_delegate = nil;
static CLLocationManager *g_location_manager = nil;

@implementation MobLocationPluginDelegate
- (void)locationManager:(CLLocationManager *)mgr didUpdateLocations:(NSArray<CLLocation *> *)locs {
  CLLocation *loc = locs.lastObject;
  if (!loc)
    return;
  ErlNifPid p = self.pid;
  double lat = loc.coordinate.latitude;
  double lon = loc.coordinate.longitude;
  double acc = loc.horizontalAccuracy;
  double alt = loc.altitude;
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    ErlNifEnv *e = enif_alloc_env();
    ERL_NIF_TERM keys[4] = {enif_make_atom(e, "lat"), enif_make_atom(e, "lon"),
                            enif_make_atom(e, "accuracy"), enif_make_atom(e, "altitude")};
    ERL_NIF_TERM vals[4] = {enif_make_double(e, lat), enif_make_double(e, lon),
                            enif_make_double(e, acc), enif_make_double(e, alt)};
    ERL_NIF_TERM map;
    enif_make_map_from_arrays(e, keys, vals, 4, &map);
    ERL_NIF_TERM msg = enif_make_tuple2(e, enif_make_atom(e, "location"), map);
    enif_send(NULL, &p, e, msg);
    enif_free_env(e);
  });
  if (self.oneShot)
    [mgr stopUpdatingLocation];
}
- (void)locationManager:(CLLocationManager *)mgr didFailWithError:(NSError *)err {
  ErlNifPid p = self.pid;
  ErlNifEnv *e = enif_alloc_env();
  ERL_NIF_TERM msg = enif_make_tuple3(e, enif_make_atom(e, "location"), enif_make_atom(e, "error"),
                                      enif_make_atom(e, "unavailable"));
  enif_send(NULL, &p, e, msg);
  enif_free_env(e);
}
- (void)locationManagerDidChangeAuthorization:(CLLocationManager *)mgr {
  CLAuthorizationStatus status = mgr.authorizationStatus;
  if (status == kCLAuthorizationStatusNotDetermined)
    return;
  if (status == kCLAuthorizationStatusAuthorizedWhenInUse ||
      status == kCLAuthorizationStatusAuthorizedAlways) {
    return;
  }
  ErlNifPid p = self.pid;
  ErlNifEnv *e = enif_alloc_env();
  ERL_NIF_TERM msg = enif_make_tuple3(e, enif_make_atom(e, "location"), enif_make_atom(e, "error"),
                                      enif_make_atom(e, "permission_denied"));
  enif_send(NULL, &p, e, msg);
  enif_free_env(e);
}
@end

static void setup_location_manager(ErlNifPid pid, BOOL oneShot, NSString *accuracy) {
  dispatch_async(dispatch_get_main_queue(), ^{
    if (!g_location_manager) {
      g_location_manager = [[CLLocationManager alloc] init];
    }
    g_location_delegate = [[MobLocationPluginDelegate alloc] init];
    g_location_delegate.pid = pid;
    g_location_delegate.oneShot = oneShot;
    g_location_manager.delegate = g_location_delegate;
    if ([accuracy isEqualToString:@"high"]) {
      g_location_manager.desiredAccuracy = kCLLocationAccuracyBest;
    } else if ([accuracy isEqualToString:@"low"]) {
      g_location_manager.desiredAccuracy = kCLLocationAccuracyKilometer;
    } else {
      g_location_manager.desiredAccuracy = kCLLocationAccuracyHundredMeters;
    }
    [g_location_manager requestWhenInUseAuthorization];
    [g_location_manager startUpdatingLocation];
  });
}

// ── NIFs ──────────────────────────────────────────────────────────────────
static ERL_NIF_TERM nif_location_get_once(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  ErlNifPid pid;
  enif_self(env, &pid);
  setup_location_manager(pid, YES, @"balanced");
  return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_location_start(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  char acc[16] = "balanced";
  enif_get_atom(env, argv[0], acc, sizeof(acc), ERL_NIF_LATIN1);
  ErlNifPid pid;
  enif_self(env, &pid);
  setup_location_manager(pid, NO, [NSString stringWithUTF8String:acc]);
  return enif_make_atom(env, "ok");
}

static ERL_NIF_TERM nif_location_stop(ErlNifEnv *env, int argc, const ERL_NIF_TERM argv[]) {
  (void)argc;
  (void)argv;
  (void)env;
  dispatch_async(dispatch_get_main_queue(), ^{
    [g_location_manager stopUpdatingLocation];
  });
  return enif_make_atom(env, "ok");
}

static int load(ErlNifEnv *env, void **priv_data, ERL_NIF_TERM load_info) {
  (void)env;
  (void)priv_data;
  (void)load_info;
  mob_register_permission_handler("location", mob_location_request_permission);
  return 0;
}

static ErlNifFunc nif_funcs[] = {
    {"location_get_once", 0, nif_location_get_once, 0},
    {"location_start", 1, nif_location_start, 0},
    {"location_stop", 0, nif_location_stop, 0},
};

ERL_NIF_INIT(mob_location_nif, nif_funcs, load, NULL, NULL, NULL)
