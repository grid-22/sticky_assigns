defmodule StickyAssigns.Store.ETS do
  @moduledoc """
  In-process ETS-backed `StickyAssigns.Store`.

  Default storage backend. Suitable for development and for production
  deployments where each LiveView mount session is guaranteed to
  reconnect to the same node (sticky sessions, single node).

  **Not suitable** for multi-node deployments without sticky sessions:
  if a dropped connection reconnects to a different node, the saved
  sticky assigns are unreachable and will fall back to defaults.

  For distributed deployments, implement `StickyAssigns.Store` against
  a shared backend (e.g. Redis, PostgreSQL) and configure:

      config :sticky_assigns, store: MyApp.MyDistributedStore
  """

  @behaviour StickyAssigns.Store

  use GenServer

  @table :sticky_assigns_store

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def get(key) do
    case :ets.lookup(@table, key) do
      [{_, value}] -> value
      [] -> %{}
    end
  end

  @impl true
  def put(key, value) do
    :ets.insert(@table, {key, value})
  end

  @impl true
  def init(args) do
    @table = :ets.new(@table, [:named_table, :public, :set])
    {:ok, args}
  end
end
