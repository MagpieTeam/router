defmodule Router.LoggerSocket do
  use Phoenix.Socket

  channel "loggers:*", Router.LoggerChannel

  transport :websocket, Phoenix.Transports.WebSocket

  def connect(%{"id" => id, "password" => password} = params, socket) do
    {:ok, logger} = Magpie.DataAccess.Logger.get(id)
    if password == logger[:password] do
      {:ok, assign(socket, :id, logger[:id])}
    else
      :error
    end
  end

  def id(_socket), do: nil

end