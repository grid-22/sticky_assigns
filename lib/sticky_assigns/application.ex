defmodule StickyAssigns.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      case Application.get_env(:sticky_assigns, :store, StickyAssigns.Store.ETS) do
        StickyAssigns.Store.ETS -> [StickyAssigns.Store.ETS]
        _custom -> []
      end

    Supervisor.start_link(children, strategy: :one_for_one, name: StickyAssigns.Supervisor)
  end
end
