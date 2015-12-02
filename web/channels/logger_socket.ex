defmodule Router.LoggerSocket do
  use Phoenix.Socket

  channel "loggers:*", Router.LoggerChannel

  transport :websocket, Phoenix.Transports.WebSocket

  def connect(%{"id" => id, "password" => password} = params, socket) do
    {:ok, logger} = Magpie.DataAccess.Logger.get(id)
    case Magpie.Password.verify_password(password, logger[:password]) do
      true -> {:ok, assign(socket, :id, logger[:id])}
      _ -> :error
    end
  end

  def id(_socket), do: nil

end