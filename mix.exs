defmodule StickyAssigns.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/grid-22/sticky_assigns"

  def project do
    [
      app: :sticky_assigns,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      description: description(),
      package: package(),
      deps: deps(),
      name: "StickyAssigns",
      source_url: @source_url,
      docs: [main: "StickyAssigns", source_url: @source_url]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {StickyAssigns.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_live_view, "~> 1.0 or ~> 0.20"},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "LiveComponent assigns that stick across remounts (dropped-connection recovery)."
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end
end
