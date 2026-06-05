%% mob_location_nif — Erlang NIF module for the location tier-1 plugin.
%%
%% iOS: priv/native/ios/mob_location_nif.m (Objective-C, CLLocationManager).
%% Android: priv/native/jni/mob_location_nif.zig (FusedLocationProviderClient
%% via the io.mob.location.MobLocationBridge Kotlin bridge). Both register this
%% module via ERL_NIF_INIT and are statically linked into the host binary on
%% device. On a host dev build neither is linked, so on_load tolerates the
%% failure and the NIFs fall back to nif_error until the native merge links one.
-module(mob_location_nif).
-export([location_get_once/0, location_start/1, location_stop/0]).
-on_load(init/0).

init() ->
    case erlang:load_nif("mob_location_nif", 0) of
        ok -> ok;
        {error, _} -> ok
    end.

location_get_once() ->
    erlang:nif_error(nif_not_loaded).

location_start(_Accuracy) ->
    erlang:nif_error(nif_not_loaded).

location_stop() ->
    erlang:nif_error(nif_not_loaded).
