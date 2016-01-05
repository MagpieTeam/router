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
    # consider using :erlang.send_after instead to avoid overhead of extra process, see http://www.erlang.org/doc/efficiency_guide/commoncaveats.html#id56802
    :timer.send_interval(@timeout, :timeout?)
    {:ok, %{last_active: Date.now(), logger_id: logger_id}}
  end

  def handle_call({:log, measurements}, _from, state) do
    result = Router.Logger.handle_log(measurements)

    {:reply, result, %{last_active: Date.now()}}
  end

  def handle_call(:stop, _from, state) do
    {:stop, {:shutdown, :left}, :ok, state}
  end
  
  def handle_info(:timeout?, %{last_active: last_active, logger_id: logger_id} = state) do
    kill_at = Date.add(last_active, Time.to_timestamp(2 * @timeout, :msecs))

    case Date.compare(Date.now(), kill_at)  do
      -1 -> {:noreply, state}
      _ -> 
        Logger.info("TIMEOUT: Logger: #{logger_id}")
        {:stop, {:shutdown, :timeout}, state}
    end
  end
end