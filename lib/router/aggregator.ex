defmodule Router.Aggregator do
  use GenServer
  alias Phoenix.Socket.Broadcast

  def start_link(sensor_id, opts \\ []) do
    GenServer.start_link(__MODULE__, sensor_id, opts)
  end

  def init(sensor_id) do
    pid = self()
    Phoenix.PubSub.subscribe(Router.PubSub, pid, "sensors:" <> sensor_id)
    {:ok, %{sensor_id: sensor_id, minutes: %{}, hours: %{}}}
  end

  def handle_info(%Broadcast{event: "new_log", payload: log}, state) do
    case accumulate(state, log) do
      %{minutes: %{done: m}, hours: %{done: h}} = state ->
        IO.puts("Minute and hour done: #{inspect m}, #{inspect h}")
        Magpie.DataAccess.Measurement.put_minute(state.sensor_id, m.timestamp, m.avg, m.min, m.max, m.count)
        minutes = Map.delete(state.minutes, :done)
        Magpie.DataAccess.Measurement.put_hour(state.sensor_id, h.timestamp, h.avg, h.min, h.max, h.count)
        hours = Map.delete(state.hours, :done)
        {:noreply, %{state | minutes: minutes, hours: hours}}
      %{minutes: %{done: m}} = state ->
        IO.puts("Minute done: #{inspect m}")
        Magpie.DataAccess.Measurement.put_minute(state.sensor_id, m.timestamp, m.avg, m.min, m.max, m.count)
        minutes = Map.delete(state.minutes, :done)
        {:noreply, %{state | minutes: minutes}}
      state -> {:noreply, state}
    end
  end

  def accumulate(state, log) do
    minute = 
      log.timestamp
      |> String.to_integer() 
      |> Kernel.*(1000)
      |> Timex.Date.from(:us)
      |> Timex.Date.set([second: 0, ms: 0, validate: false])

    hour = Timex.Date.set(minute, [minute: 0, validate: false])

    {value, _} = Float.parse(log.value)
    minutes = case Map.get(state.minutes, minute) do
      nil ->
        acc = create_accumulator(minute, value)
        minutes = Map.put(state.minutes, minute, acc)
        # write the accumulator from last minute to DB
        last_minute = Timex.Date.shift(minute, mins: -1)
        case Map.get(state.minutes, last_minute) do
          nil ->
            minutes
          acc ->
            avg = acc.sum / acc.count
            minutes = Map.put(state.minutes, :done, %{acc | avg: avg})
            Map.delete(minutes, last_minute)
        end
      acc ->
        new_acc = add_to_accumulator(acc, value)
        Map.put(state.minutes, minute, new_acc)
    end

    hours = case Map.get(state.hours, hour) do
      nil ->
        acc = create_accumulator(hour, value)
        hours = Map.put(state.hours, hour, acc)
        last_hour = Timex.Date.shift(hour, hours: -1)
        case Map.get(state.hours, last_hour) do
          nil ->
            hours
          acc ->
            avg = acc.sum / acc.count
            hours = Map.put(state.hours, :done, %{acc | avg: avg})
            Map.delete(hours, last_hour)
        end
      acc ->
        new_acc = add_to_accumulator(acc, value)
        Map.put(state.hours, hour, new_acc)
    end

    %{state | minutes: minutes, hours: hours}
  end

  defp create_accumulator(timestamp, value) do
    %{timestamp: timestamp, count: 1, sum: value, min: value, max: value, avg: 0}
  end

  defp add_to_accumulator(acc, value) do
    %{acc |
      count: acc.count + 1,
      sum: acc.sum + value,
      min: min(acc.min, value),
      max: max(acc.max, value), 
    }
  end
end

# Inserting hour 15
# New hourly accumulator
# New hourly accumulator
# New hourly accumulator
# Inserting hour 15
# Inserting hour 15
# Inserting hour 15
# Accumulator: %{count: 1227, max: 99.95851994026452, min: 0.008757202886044979, sum: 61875.18161109183}
# Accumulator: %{count: 1227, max: 99.95851994026452, min: 0.008757202886044979, sum: 61875.18161109183}
# Accumulator: %{count: 1227, max: 99.95851994026452, min: 0.008757202886044979, sum: 61875.18161109183}
# Accumulator: %{count: 1227, max: 99.95851994026452, min: 0.008757202886044979, sum: 61875.18161109183}
# Average: 50.42802087293548
# Average: 50.42802087293548
# Average: 50.42802087293548
# Average: 50.42802087293548
# sensor-id: e70a04d2-8c01-4505-a782-b2f0e497cb33
# sensor-id: b5ac0269-7d6f-456d-8ce7-048dc5740424
# sensor-id: 049eb9c5-236d-4581-a7a1-57f5f5a3e4ca
# sensor-id: 4300b8cd-d361-447a-9f70-4198a64fe08f
# Got :DOWN {:DOWN, #Reference<0.0.3.2218>, :process, #PID<0.483.0>, {:badarg, [{:erlang, :apply, [99.95851994026452, :acc, []], []}, {Router.Aggregator, :handle_info, 2, [file: 'lib/router/aggregator.ex', line: 62]}, {:gen_server, :try_dispatch, 4, [file: 'gen_server.erl', line: 615]}, {:gen_server, :handle_msg, 5, [file: 'gen_server.erl', line: 681]}, {:proc_lib, :init_p_do_apply, 3, [file: 'proc_lib.erl', line: 240]}]}}
# [error] GenServer #PID<0.489.0> terminating
# ** (ArgumentError) argument error
#     :erlang.apply(99.95851994026452, :acc, [])
#     (router) lib/router/aggregator.ex:62: Router.Aggregator.handle_info/2
#     (stdlib) gen_server.erl:615: :gen_server.try_dispatch/4
#     (stdlib) gen_server.erl:681: :gen_server.handle_msg/5
#     (stdlib) proc_lib.erl:240: :proc_lib.init_p_do_apply/3
# Last message: %Phoenix.Socket.Broadcast{event: "new_log", payload: %{metadata: "AAAF", sensor_id: "e70a04d2-8c01-4505-a782-b2f0e497cb33", timestamp: "1451487600394", value: "89.36654648277909"}, topic: "sensors:e70a04d2-8c01-4505-a782-b2f0e497cb33"}
# State: %{hours: %{%Timex.DateTime{calendar: :gregorian, day: 30, hour: 14, minute: 0, month: 12, ms: 0, second: 0, timezone: %Timex.TimezoneInfo{abbreviation: "UTC", from: :min, full_name: "UTC", offset_std: 0, offset_utc: 0, until: :max}, year: 2015} => %{count: 1227, max: 99.95851994026452, min: 0.008757202886044979, sum: 61875.18161109183}}, minutes: %{%Timex.DateTime{calendar: :gregorian, day: 30, hour: 14, minute: 59, month: 12, ms: 0, second: 0, timezone: %Timex.TimezoneInfo{abbreviation: "UTC", from: :min, full_name: "UTC", offset_std: 0, offset_utc: 0, until: :max}, year: 2015} => %{count: 29, max: 98.95174847915769, min: 2.793678012676537, sum: 1637.0547903468832}}, sensor_id: "e70a04d2-8c01-4505-a782-b2f0e497cb33"}