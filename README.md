# StickyAssigns

**LiveComponent assigns that stick across remounts.**

When a Phoenix LiveView's WebSocket drops and reconnects, the LV process is destroyed and a fresh one mounts in its place. By default, all in-process state — including LiveComponent assigns like "which tab is open" or "what's typed into this dialog" — is lost. For transient-but-meaningful UI state, that loss is jarring.

StickyAssigns lets you declare specific LC assigns as *sticky*. They survive a remount within the same mount session (dropped-connection recovery) but are deliberately discarded on refresh, navigation, or any hard reset — those are user-initiated and should clear transient state.

## What this is not

- Not for persistent (database-backed) data — use the URL or your context modules.
- Not for cross-session state — that belongs in the database.
- Not a replacement for forms with proper validation/errors.

StickyAssigns is for *transient state that should survive a network blip*. Nothing more.

## Installation

```elixir
def deps do
  [
    {:sticky_assigns, "~> 0.1.0"}
  ]
end
```

Optional configuration (defaults shown):

```elixir
config :sticky_assigns, store: StickyAssigns.Store.ETS
```

The application supervisor starts the ETS store automatically.

## Usage

In your LiveView's `mount/3`:

```elixir
def mount(_params, _session, socket) do
  {:ok, StickyAssigns.mount(socket)}
end
```

In your LiveComponent's `update/2`, declare which assigns are sticky on the *first* call (when `:id` has arrived but isn't yet in `socket.assigns`). A second clause handles subsequent calls:

```elixir
def update(%{id: id} = assigns, socket)
    when not is_map_key(socket.assigns, :id) do
  socket =
    socket
    |> StickyAssigns.recover(id, tab: :general, expanded: false)
    |> assign(assigns)

  {:ok, socket}
end

def update(assigns, socket), do: {:ok, assign(socket, assigns)}
```

Defaults are recorded on the *first* call for a given component; subsequent calls to `recover/3` are no-ops and silently ignore their `defaults` argument. The guard above makes that lifetime explicit.

In the same LC's `render/1`, write back any changes:

```elixir
def render(assigns) do
  StickyAssigns.preserve(assigns)
  ~H"""
  ...
  """
end
```

That's the whole API. Three functions.

## How it works

The store key is the WebSocket CSRF token (not the LV pid). On the *first* mount, an empty entry is created for the token. On a *remount* (same mount session, new LV process), the token is the same and the saved state is loaded.

`recover/3` reads the saved state for `component_id` and assigns it on top of the supplied defaults. `preserve/1` diffs current assigns against those defaults and writes any deltas back. Components matching defaults exactly are *not* stored — the store stays small.

Because the token is re-issued on full page load, state is discarded on refresh — exactly the lifetime we want for transient UI state.

## Storage backends

The default `StickyAssigns.Store.ETS` is in-process and not distributed. **Suitable for development and for single-node production deployments (or multi-node with sticky sessions).** If a dropped connection reconnects to a different node, the saved state is unreachable and recovery falls back to defaults.

For distributed deployments, implement the `StickyAssigns.Store` behaviour against a shared backend:

```elixir
defmodule MyApp.RedisStickyStore do
  @behaviour StickyAssigns.Store

  def get(token), do: # ...
  def put(token, cache), do: # ...
end
```

```elixir
config :sticky_assigns, store: MyApp.RedisStickyStore
```

## Roadmap

- Session-scope as an opt-in (`recover(socket, id, defaults, scope: :session)`) — state survives full page reloads. Storage already supports this; v0.1 enforces mount-scope as a policy choice. See `TODO.md` for the design sketch.
- Built-in Redis backend
- LiveView-level (not just LC-level) recovery
- TTL / size limits on the ETS backend

## License

MIT
