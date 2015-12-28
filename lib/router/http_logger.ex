defmodule Router.HttpLogger do
  use GenServer
  use Timex

  @timeout 30000

  def start(logger_id, opts \\ []) do
    GenServer.start(__MODULE__, logger_id, opts)
  end

  def stop(logger_pid) do
    GenServer.call(logger_pid, :stop)
  end

  def log(logger_pid, measurements) do
    GenServer.call(logger_pid, {:log, measurements})
  end

  def init(logger_id) do
    :ok = Router.Presence.register(logger_id, self())
    sensors = Magpie.DataAccess.Sensor.get(logger_id)
    Enum.each(sensors, fn (s) -> Router.Aggregator.start_link(to_string(s[:id])) end)

    :timer.send_interval(@timeout, :timeout?)
    {:ok, %{last_active: Date.now()}}
  end

  def handle_call({:log, measurements}, _from, state) do
    IO.puts("Logging #{inspect measurements}")
    result = Router.Logger.handle_log(measurements)

    {:reply, result, %{last_active: Date.now()}}
  end

  def handle_call(:stop, _from, state) do
    {:stop, {:shutdown, :left}, :ok, state}
  end
  
  def handle_info(:timeout?, %{last_active: last_active} = state) do
    IO.puts("got timeout?")
    kill_at = Date.add(last_active, Time.to_timestamp(2 * @timeout, :msecs))

    case Date.compare(Date.now(), kill_at)  do
      -1 -> {:noreply, state}
      _ -> {:stop, {:shutdown, :timeout}, state}
    end
  end
end