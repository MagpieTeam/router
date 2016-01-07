defmodule Router.LoggerController do
  use Router.Web, :controller

  def index(conn, _params) do
    conn
    |> assign(:loggers, Magpie.DataAccess.Logger.get())
    |> render("index.html")
  end

  def show(conn, params) do
    {:ok, logger} = Magpie.DataAccess.Logger.get(params["id"])
    sensors = Magpie.DataAccess.Sensor.get(params["id"])
    conn
    |> assign(:logger, logger)
    |> assign(:sensors, sensors)
    |> render("show.html")
  end

  def start(conn, params) do
    {:ok, logger} = Magpie.DataAccess.Logger.get(params["logger_id"])
    sensors = Magpie.DataAccess.Sensor.get(logger[:id]) |> Enum.count()
    case Router.LoadRegulator.permit?(sensors) do
      true ->
        {:ok, logger_pid} = Router.HttpLogger.start(logger[:id], logger[:name])
        token = Phoenix.Token.sign(Router.Endpoint, "logger", logger_pid)
        json(conn, %{token: token})
      false ->
        conn
        |> Plug.Conn.put_status(503)
        |> json("request denied by load regulator")
    end
  end

  def stop(conn, params) do
    token = params["token"]
    {:ok, logger_pid} = Phoenix.Token.verify(Router.Endpoint, "logger", token)
    Router.HttpLogger.stop(logger_pid)
    json(conn, nil)
  end

  def log(conn, params) do
    measurements = params["measurements"]
    token = params["token"]
    case Phoenix.Token.verify(Router.Endpoint, "logger", token) do
      {:ok, logger_pid} ->
        case Router.HttpLogger.log(logger_pid, measurements) do
          :ok ->
            json(conn, nil)
          {:error, reason} ->
            conn
            |> Plug.Conn.put_status(500)
            |> json(reason)
        end
      {:error, :invalid} ->
        conn
        |> Plug.Conn.put_status(400)
        |> json("invalid token")
    end    
  end

  def configure(conn, params) do
    logger_id = params["logger_id"]
    new_sensors = params["sensors"]
    {:ok, logger} = Magpie.DataAccess.Logger.get(logger_id)
    sensors = Magpie.DataAccess.Sensor.get(logger_id)

    passive_sensors = Enum.reduce(sensors, [], fn(s, acc) -> 
      case Enum.find(new_sensors, nil, fn(new_sensor) -> new_sensor["id"] == s[:id] end) do
        nil -> [to_string(s[:id]) | acc]
        _ -> acc
      end
    end)

    Magpie.DataAccess.Sensor.set_passive(passive_sensors, logger_id)
    Magpie.DataAccess.Sensor.put(new_sensors, logger_id)

    # TODO: send kill message to presence

    json(conn, nil)
  end
end