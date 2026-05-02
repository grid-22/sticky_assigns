defmodule StickyAssignsTest do
  use ExUnit.Case, async: false

  alias StickyAssigns.Store.ETS, as: Store

  setup do
    # PD is per-process so naturally isolated. Clear the ETS store between
    # tests so token-keyed entries don't bleed across them.
    :ets.delete_all_objects(:sticky_assigns_store)
    :ok
  end

  # The recover/3 path branches on Process dictionary state set by mount/1.
  # We exercise that state directly here rather than spinning up a real LV;
  # an end-to-end test using Phoenix.LiveViewTest is captured in TODO.md.

  describe "recover/3 — first call (no :id in assigns)" do
    test "raises if mount/1 was not called" do
      Process.delete(:sticky_assigns_token)
      Process.delete(:sticky_assigns_defaults)
      socket = build_socket(%{})

      assert_raise RuntimeError, ~r/StickyAssigns.recover\/3 called before/, fn ->
        StickyAssigns.recover(socket, "comp-1", tab: :general)
      end
    end

    test "on dead render, assigns the defaults" do
      simulate_dead_render()
      socket = build_socket(%{})

      result = StickyAssigns.recover(socket, "comp-1", tab: :general, expanded: false)
      assert result.assigns.tab == :general
      assert result.assigns.expanded == false
    end

    test "on initial connected mount with no saved state, assigns defaults" do
      simulate_initial_mount("token-a")
      socket = build_socket(%{})

      result = StickyAssigns.recover(socket, "comp-1", tab: :general, expanded: false)
      assert result.assigns.tab == :general
      assert result.assigns.expanded == false
    end

    test "on remount with saved state, restores it on top of defaults" do
      simulate_remount("token-b", %{"comp-1" => %{tab: :advanced}})
      socket = build_socket(%{})

      result = StickyAssigns.recover(socket, "comp-1", tab: :general, expanded: false)
      assert result.assigns.tab == :advanced
      assert result.assigns.expanded == false
    end

    test "remembers declared defaults for later preserve/1 to diff against" do
      simulate_initial_mount("token-c")
      socket = build_socket(%{})

      _ = StickyAssigns.recover(socket, "comp-1", tab: :general, expanded: false)

      defaults = Process.get(:sticky_assigns_defaults)
      assert defaults["comp-1"] == %{tab: :general, expanded: false}
    end
  end

  describe "recover/3 — subsequent call (:id already in assigns)" do
    test "is a no-op" do
      simulate_initial_mount("token-d")
      socket = build_socket(%{id: "comp-1", tab: :general})

      result = StickyAssigns.recover(socket, "comp-1", tab: :ignored)
      assert result.assigns.id == "comp-1"
      assert result.assigns.tab == :general
    end

    test "asserts that the component_id matches" do
      simulate_initial_mount("token-e")
      socket = build_socket(%{id: "comp-1"})

      assert_raise MatchError, fn ->
        StickyAssigns.recover(socket, "different-id", tab: :general)
      end
    end
  end

  describe "preserve/1" do
    test "writes changed assigns to the cache and store" do
      simulate_initial_mount("token-f")
      register_defaults("comp-1", %{tab: :general, expanded: false})

      assigns = %{id: "comp-1", tab: :advanced, expanded: false}

      assert :ok = StickyAssigns.preserve(assigns)

      cache = Process.get(:sticky_assigns_cache)
      assert cache["comp-1"] == %{tab: :advanced, expanded: false}
      assert Store.get("token-f")["comp-1"] == %{tab: :advanced, expanded: false}
    end

    test "does not write when assigns equal current cache state" do
      simulate_initial_mount("token-g")
      register_defaults("comp-1", %{tab: :general})

      assigns = %{id: "comp-1", tab: :advanced}
      StickyAssigns.preserve(assigns)
      Store.put("token-g", %{"sentinel" => true})

      StickyAssigns.preserve(assigns)
      assert Store.get("token-g") == %{"sentinel" => true}
    end

    test "removes the entry from the cache when assigns equal defaults" do
      simulate_initial_mount("token-h")
      register_defaults("comp-1", %{tab: :general})

      StickyAssigns.preserve(%{id: "comp-1", tab: :advanced})
      assert Process.get(:sticky_assigns_cache)["comp-1"] == %{tab: :advanced}

      StickyAssigns.preserve(%{id: "comp-1", tab: :general})
      refute Map.has_key?(Process.get(:sticky_assigns_cache), "comp-1")
    end

    test "ignores assign keys not declared in defaults" do
      simulate_initial_mount("token-i")
      register_defaults("comp-1", %{tab: :general})

      assigns = %{id: "comp-1", tab: :advanced, irrelevant: "noise"}
      StickyAssigns.preserve(assigns)

      assert Store.get("token-i")["comp-1"] == %{tab: :advanced}
    end

    test "no-op on dead render" do
      simulate_dead_render()
      assert :ok = StickyAssigns.preserve(%{id: "comp-1", tab: :advanced})
    end

    test "no-op when component was never recovered" do
      simulate_initial_mount("token-j")
      assert :ok = StickyAssigns.preserve(%{id: "never-recovered", tab: :advanced})
      assert Store.get("token-j") == %{}
    end
  end

  describe "Store.ETS" do
    test "get returns empty map for unknown key" do
      assert Store.get("missing") == %{}
    end

    test "put + get round-trip" do
      Store.put("k", %{"comp" => %{n: 1}})
      assert Store.get("k") == %{"comp" => %{n: 1}}
    end

    test "put overwrites" do
      Store.put("k", %{"comp" => %{n: 1}})
      Store.put("k", %{"comp" => %{n: 2}})
      assert Store.get("k") == %{"comp" => %{n: 2}}
    end
  end

  # ── Helpers ────────────────────────────────────────────────────────────────

  defp simulate_dead_render do
    Process.put(:sticky_assigns_token, :dead_render)
  end

  defp simulate_initial_mount(token) do
    Process.put(:sticky_assigns_token, token)
    Process.put(:sticky_assigns_defaults, %{})
    Process.put(:sticky_assigns_cache, %{})
    Store.put(token, %{})
  end

  defp simulate_remount(token, saved_state) do
    Process.put(:sticky_assigns_token, token)
    Process.put(:sticky_assigns_defaults, %{})
    Process.put(:sticky_assigns_cache, saved_state)
    Store.put(token, saved_state)
  end

  defp register_defaults(component_id, defaults) do
    all = Process.get(:sticky_assigns_defaults) || %{}
    Process.put(:sticky_assigns_defaults, Map.put(all, component_id, defaults))
  end

  defp build_socket(assigns) do
    %Phoenix.LiveView.Socket{
      assigns: Map.merge(%{__changed__: %{}}, assigns)
    }
  end
end
