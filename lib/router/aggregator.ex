defmodule Router.Aggregator do
  use GenServer
  alias Phoenix.Socket.Broadcast

  def start_link(sensor_id, opts \\ []) do
    GenServer.start_link(__MODULE__, sensor_id, opts)
  end

  def init(sensor_id) do
    pid = self()
    Phoenix.PubSub.subscribe(Router.PubSub, pid, "sensors:" <> sensor_id)
    {:ok, %{sensor_id: sensor_id}}
  end

  def handle_info(%Broadcast{event: "new_log", payload: log}, state) do
    minute = 
      log.timestamp
      |> String.to_integer() 
      |> Kernel.*(1000)
      |> Timex.Date.from(:us)
      |> Timex.Date.set([second: 0, ms: 0, validate: false])

    value = String.to_float(log.value)
    state = case Map.get(state, minute) do
      nil ->
        acc = create_accumulator(value)
        state = Map.put(state, minute, acc)
        # write the accumulator from last minute to DB
        last_minute = Timex.Date.shift(minute, mins: -1)
        case Map.get(state, last_minute) do
          nil -> 
            state
          acc ->
            avg = acc.sum / acc.count
            Magpie.DataAccess.Measurement.put_minute(state.sensor_id, last_minute, avg, acc.min, acc.max, acc.count)
            Map.delete(state, last_minute)
        end
      acc ->
        new_acc = add_to_accumulator(acc, value)
        Map.put(state, minute, new_acc)
    end

    {:noreply, state}
  end

  defp create_accumulator(value) do
    %{count: 1, sum: value, min: value, max: value}
  end

  defp add_to_accumulator(acc, value) do
    %{
      count: acc.count + 1,
      sum: acc.sum + value,
      min: min(acc.min, value),
      max: max(acc.max, value), 
    }
  end
end