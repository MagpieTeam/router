defmodule Router.NodeController do
  use Router.Web, :controller

  def index(conn, _params) do
    nodes = 
      :ets.match(:nodes, :"$1")
      |> Enum.map(fn ([ n | _ ]) -> %{node: elem(n, 0), ip: elem(n, 1)} end)
    json(conn, nodes)
  end
end