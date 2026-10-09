defmodule MobLocationTest do
  use ExUnit.Case, async: true

  alias MobDev.Plugin.{Manifest, Validator}
  alias MobLocation.SelfTest

  @plugin_dir Path.expand("..", __DIR__)

  describe "plugin manifest" do
    setup do
      {:ok, manifest} = Manifest.load(@plugin_dir)
      %{manifest: manifest}
    end

    test "loads and validates clean (round-trips)", %{manifest: m} do
      assert {:ok, ^m} = Manifest.validate(m)
    end

    test "classifies as tier 3 (NIF + a demo screen)", %{manifest: m} do
      # The capability NIF alone is tier 1; the bundled demo screen (a tier-3
      # :screens section) lifts it to 3. tier/1 reports the highest section.
      assert Manifest.tier(m) == 3
    end

    test "passes the full pre-publish validator (paths, NIF modules, permissions)",
         %{manifest: m} do
      assert %{errors: []} = Validator.validate_plugin(m, @plugin_dir)
    end

    test "declares the cross-platform NIF pattern: one module, both platforms",
         %{manifest: m} do
      assert [ios, android] = m.nifs
      assert ios.module == :mob_location_nif and ios.platform == :ios and ios.lang == :objc
      assert android.module == :mob_location_nif and android.platform == :android
      assert android.lang == :zig
    end

    test "owns the :location capability with the iOS self-registered handler",
         %{manifest: m} do
      assert [%{capability: :location, ios: %{handler: "mob_location_request_permission"}}] =
               m.permissions
    end

    test "every native source dir + Kotlin bridge the manifest references exists",
         %{manifest: m} do
      for %{native_dir: dir} <- m.nifs do
        assert File.dir?(Path.join(@plugin_dir, dir)), "missing #{dir}"
      end

      assert File.exists?(Path.join(@plugin_dir, m.android.bridge_kt))
    end

    test "declares the self-test, which passes the validator without a warning", %{manifest: m} do
      assert m.selftest == MobLocation.SelfTest
      assert %{errors: [], warnings: warnings} = Validator.validate_plugin(m, @plugin_dir)
      refute Enum.any?(warnings, &(&1 =~ "selftest"))
    end
  end

  describe "MobLocation.SelfTest" do
    test "on a host with no native library linked it fails, naming the NIF, instead of raising" do
      assert {:fail, reason} = SelfTest.run(%{platform: :android, device: :emulator})
      assert reason =~ "mob_location_nif is not linked"
      assert reason =~ "nif_not_loaded"
      assert Mob.Plugin.SelfTest.result?({:fail, reason})
    end

    test "classifies every delivery the native side can send after get_once" do
      send(self(), {:location, %{lat: 45.5, lon: -73.6, accuracy: 10.0, altitude: 30.0}})
      assert SelfTest.await_answer(0, :android) == :pass

      send(self(), {:location, :error, :unavailable})
      assert SelfTest.await_answer(0, :ios) == :pass

      send(self(), {:location, :error, :permission_denied})
      assert SelfTest.await_answer(0, :android) == {:skip, :needs_user}

      send(self(), {:location, :error, :no_activity})

      assert {:fail, "MobLocationBridge has no Activity" <> _} =
               SelfTest.await_answer(0, :android)

      send(self(), {:location, :error, :bogus})

      assert {:fail, "location_get_once/0 delivered error :bogus" <> _} =
               SelfTest.await_answer(0, :android)

      send(self(), {:location, "nope"})

      assert {:fail, "location_get_once/0 delivered \"nope\"" <> _} =
               SelfTest.await_answer(0, :ios)
    end

    test "no answer is a skip: pending request on Android, the user's prompt on iOS" do
      assert {:skip, "location_get_once/0 got no answer in 0 s" <> _} =
               SelfTest.await_answer(0, :android)

      assert SelfTest.await_answer(0, :ios) == {:skip, :needs_user}
    end
  end

  describe "NIF stub agreement" do
    # Guards the .erl stub / manifest, not app code — VacuousTest can't see that.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "the manifest NIF module is the shipped .erl stub and loads on the host" do
      assert Code.ensure_loaded?(:mob_location_nif)
    end

    # Guards the .erl stub / manifest, not app code — VacuousTest can't see that.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "every NIF the public API calls is exported by the stub at the right arity" do
      exports = :mob_location_nif.module_info(:exports)

      for fa <- [location_get_once: 0, location_start: 1, location_stop: 0] do
        assert fa in exports, "#{inspect(fa)} missing from mob_location_nif exports"
      end
    end

    # Guards the .erl stub / manifest, not app code — VacuousTest can't see that.
    # credo:disable-for-next-line Jump.CredoChecks.VacuousTest
    test "host (no native linked) falls back to nif_not_loaded, not a load crash" do
      assert_raise ErlangError, ~r/nif_not_loaded/, fn ->
        :mob_location_nif.location_stop()
      end
    end
  end

  describe "public API surface (extraction parity with old Mob.Location)" do
    test "exports the extracted surface" do
      exports = MobLocation.__info__(:functions)

      for fa <- [get_once: 1, start: 2, stop: 1] do
        assert fa in exports, "#{inspect(fa)} missing from MobLocation"
      end
    end
  end
end
