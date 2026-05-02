defmodule StickyAssigns.Store do
  @moduledoc """
  Behaviour for sticky-assigns storage backends.

  A store maps a `mount_token` (the WebSocket CSRF token) to a map of
  `component_id => sticky_assigns`. The default backend is
  `StickyAssigns.Store.ETS`.

  Implementations must be safe to call from any process. They do not
  need to handle missing keys specially — `get/1` returns `%{}` when
  no entry exists.

  ## Custom backends

  Implement this behaviour for distributed or persistent storage
  (e.g. Redis, PostgreSQL):

      defmodule MyApp.RedisStickyAssignsStore do
        @behaviour StickyAssigns.Store
        # ...
      end

  Then configure:

      config :sticky_assigns, store: MyApp.RedisStickyAssignsStore
  """

  @type token :: String.t()
  @type cache :: %{optional(String.t() | :root) => map()}

  @callback get(token()) :: cache()
  @callback put(token(), cache()) :: any()
end
