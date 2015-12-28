defmodule Router.HttpLogger do
  use GenServer

  def start(logger_id, opts \\ []) do
    IO.puts("Starting #{logger_id}")
    GenServer.start(__MODULE__, logger_id, opts)
  end

  def stop(logger_pid) do
    GenServer.call(logger_pid, :stop)
  end

  def log(logger_pid, measurements) do
    GenServer.call(logger_pid, {:log, measurements})
  end

  def init(logger_id) do
    IO.puts("Starting #{logger_id}")
    :ok = Router.Presence.register(logger_id, self())
    sensors = Magpie.DataAccess.Sensor.get(logger_id)
    IO.inspect({"sensors", sensors})
    Enum.each(sensors, fn (s) -> Router.Aggregator.start_link(to_string(s[:id])) end)
    IO.puts("Ending")
    # TODO: schedule kill message
    {:ok, %{}}
  end

  def handle_call({:log, measurements}, _from, state) do
    IO.puts("Logging #{inspect measurements}")
    result = Router.Logger.handle_log(measurements)

    # TODO: update timeout
    {:reply, result, state}
  end

  def handle_call(:stop, _from, state) do
    {:stop, :normal, :ok, state}
  end
  
end