defmodule StickyAssigns do
  @moduledoc """
  LiveComponent assigns that stick across remounts.

  When a Phoenix LiveView's WebSocket drops and reconnects, the LV process
  is destroyed and a fresh one mounts in its place. By default, all
  in-process state (including LiveComponent assigns) is lost. For an open
  dialog mid-form, an inspector with selected tabs, or any "transient but
  meaningful" UI state, that loss is jarring — even though the URL is
  still valid.

  StickyAssigns lets you declare specific LiveComponent assigns as
  *sticky*. They survive a remount within the same mount session
  (dropped-connection recovery) but are deliberately discarded on
  refresh, navigation, or any other hard reset — those are user-initiated
  resets and should clear transient UI state.

  ## What this is not

  Not for persistent (database-backed) data — use the URL or your context
  modules. Not for cross-session state — that belongs in the database.
  StickyAssigns is for *transient state that should survive a network
  blip*, nothing more.

  ## Setup

  Configure the storage backend (defaults to `StickyAssigns.Store.ETS`):

      config :sticky_assigns, store: StickyAssigns.Store.ETS

  Add the application to your supervision tree (handled automatically
  if you depend on `:sticky_assigns` — its application starts the ETS
  store).

  ## Usage

  In your LiveView's `mount/3`:

      def mount(_params, _session, socket) do
        {:ok, StickyAssigns.mount(socket)}
      end

  In your LiveComponent's `update/2` (the *first* time through, before
  `:id` is in assigns), declare which assigns are sticky and their
  defaults:

      def update(%{id: id} = assigns, socket) do
        socket =
          socket
          |> StickyAssigns.recover(id, tab: :general, expanded: false)
          |> assign(assigns)

        {:ok, socket}
      end

  In the same LC's `render/1`, call `preserve/1` to write back any
  changes:

      def render(assigns) do
        StickyAssigns.preserve(assigns)
        ~H"\""
        ...
        "\""
      end

  ## How it works

  On the *first* mount, `mount/1` reads the CSRF token from the
  WebSocket connect params and creates an empty store entry keyed by
  that token. On a *remount* (same mount session, new process), the
  same token is sent — `mount/1` finds the existing entry and the
  process is initialised from the saved state.

  `recover/3` reads the saved state for the given `component_id` from
  the in-process cache and assigns it onto the socket, falling back to
  the supplied defaults if no saved state exists.

  `preserve/1` diffs current assigns against the defaults; if anything
  changed, it writes the changed assigns back to the store. Unchanged
  values are deliberately not stored, so the store stays small.

  Because the store key is the CSRF token (not the LV pid), state
  survives the LV process being recreated. Because the token is
  re-issued on full page load, state is discarded on refresh — exactly
  the lifetime we want for transient UI state.

  ## Limitations

  * Currently recovers assigns for LiveComponents only, not LiveViews.
  * Only ephemeral state (lifetime = mount session). Cross-session
    persistence is on the roadmap as an opt-in.
  * The default `StickyAssigns.Store.ETS` backend is in-process and
    not distributed. If your LV reconnects to a different node behind
    a load balancer, the saved state is unreachable. Sticky sessions
    or a distributed store (e.g. Redis) are required for production
    behind multiple nodes.
  """

  @token_key :sticky_assigns_token
  @cache_key :sticky_assigns_cache
  @defaults_key :sticky_assigns_defaults

  import Phoenix.Component, only: [assign: 2]
  import Phoenix.LiveView, only: [get_connect_params: 1, connected?: 1]

  require Logger

  defp store do
    Application.get_env(:sticky_assigns, :store, StickyAssigns.Store.ETS)
  end

  @doc """
  Initialise sticky-assign tracking for this LiveView mount.

  Call from your LiveView's `mount/3`:

      def mount(_, _, socket) do
        {:ok, StickyAssigns.mount(socket)}
      end

  On the initial connected mount, this creates an empty store entry
  keyed by the WebSocket CSRF token. On a remount (same mount session,
  new process — e.g. after a dropped connection), this loads the
  existing store entry into the process's local cache.

  On the dead render (initial HTTP request before WebSocket connect),
  this is a no-op; `recover/3` will fall back to defaults.
  """
  @spec mount(Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def mount(socket) do
    if connected?(socket) do
      Logger.debug("#{__MODULE__}.mount connected, pid=#{inspect(self())}")

      case get_connect_params(socket) do
        %{"_mounts" => 0, "_csrf_token" => token} ->
          Process.put(@token_key, token)
          Process.put(@defaults_key, %{})
          store().put(token, %{})
          Process.put(@cache_key, %{})
          Logger.debug("StickyAssigns.mount(#{token}) initial mount pid=#{inspect(self())}")

        %{"_mounts" => mount_count, "_csrf_token" => token} ->
          Process.put(@token_key, token)
          Process.put(@defaults_key, %{})
          data = store().get(token)
          Process.put(@cache_key, data)

          Logger.debug(
            "StickyAssigns.mount(#{token}) remount\##{mount_count} -> #{inspect(data)}"
          )
      end

      socket
    else
      Process.put(@token_key, :dead_render)
      socket
    end
  end

  @doc """
  Declare which assigns are sticky (with their defaults) and recover any
  saved state.

  Call from your LiveComponent's `update/2`, on the first pass through
  (when `:id` is not yet in assigns):

      def update(%{id: id} = assigns, socket) do
        socket =
          socket
          |> StickyAssigns.recover(id, tab: :general, expanded: false)
          |> assign(assigns)

        {:ok, socket}
      end

  The defaults define the *shape* of the sticky state — only these keys
  are persisted, even if the assigns map contains others. Subsequent
  calls to `recover/3` for the same component (with `:id` already in
  assigns) are no-ops aside from a sanity check that the id matches.

  Raises `RuntimeError` if `mount/1` was not called from the LiveView.
  """
  @spec recover(
          Phoenix.LiveView.Socket.t(),
          String.t() | :root,
          keyword()
        ) :: Phoenix.LiveView.Socket.t()
  def recover(socket, component_id, defaults)

  def recover(%{assigns: assigns} = socket, component_id, defaults)
      when (component_id == :root or is_binary(component_id)) and
             not is_map_key(assigns, :id) do
    defaults = Map.new(defaults)

    case {Process.get(@token_key), Process.get(@defaults_key)} do
      {nil, nil} ->
        raise RuntimeError,
              "StickyAssigns.recover/3 called before StickyAssigns.mount/1 — " <>
                "did you forget to call StickyAssigns.mount(socket) in your LiveView's mount/3?"

      {:dead_render, nil} ->
        Logger.debug("StickyAssigns.recover/3 dead render, #{component_id} -> defaults")
        assign(socket, defaults)

      {token, all_defaults} when is_binary(token) and is_map(all_defaults) ->
        Process.put(@defaults_key, Map.put(all_defaults, component_id, defaults))

        case Map.get(Process.get(@cache_key), component_id) do
          nil -> assign(socket, defaults)
          data when is_map(data) -> socket |> assign(defaults) |> assign(data)
        end
    end
  end

  def recover(%{assigns: %{id: id}} = socket, assigns_id, _) when is_binary(assigns_id) do
    ^id = assigns_id
    Logger.debug("StickyAssigns.recover/3 #{assigns_id} already recovered, ignoring")
    socket
  end

  @doc """
  Preserve any changes to sticky assigns to the backing store.

  Call from your LiveComponent's `render/1`:

      def render(assigns) do
        StickyAssigns.preserve(assigns)
        ~H"\""
        ...
        "\""
      end

  Diffs the current assigns against the declared defaults; if any sticky
  key has a non-default value (and differs from what's already saved),
  writes the change to the store. Unchanged components are not written.

  No-op on dead render or if `recover/3` was never called for this
  component.
  """
  @spec preserve(map()) :: :ok
  def preserve(assigns) do
    with token when is_binary(token) <- Process.get(@token_key),
         cache <- Process.get(@cache_key),
         default_assigns when is_map(default_assigns) <-
           Map.get(Process.get(@defaults_key), assigns.id),
         effective_saved_assigns =
           Map.merge(default_assigns, Map.get(cache, assigns.id) || %{}),
         updated_assigns = Map.take(assigns, Map.keys(default_assigns)) do
      if updated_assigns != effective_saved_assigns do
        new_cache =
          if updated_assigns == default_assigns do
            Map.delete(cache, assigns.id)
          else
            Map.put(cache, assigns.id, updated_assigns)
          end

        Process.put(@cache_key, new_cache)
        store().put(token, new_cache)
      end
    end

    :ok
  end
end
