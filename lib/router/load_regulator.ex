defmodule Router.LoadRegulator do
  use GenServer
  require Logger

  @max_tokens 500
  @refill_interval 1000
  @max_refill_amount 500
  @normal_load 0.3
  @max_load 0.7

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def permit?(sensors) do
    GenServer.call(Router.LoadRegulator, {:permit?, sensors})
  end

  def init(:ok) do
    :timer.send_interval(@refill_interval, :refill)
    slope = - @max_refill_amount / (@max_load - @normal_load)
    y_intercept = @max_refill_amount - slope * @normal_load 

    {:ok, %{tokens: @max_tokens, slope: slope, y_intercept: y_intercept}}
  end

  def handle_call({:permit?, requested_tokens}, _from, %{tokens: current_tokens} = state) do
    tokens_next = current_tokens - requested_tokens
    Logger.debug("Tokens available after request: #{tokens_next}")
    case tokens_next > -1 do
      true -> {:reply, true, %{state | tokens: tokens_next}}
      false -> {:reply, false, state}
    end
  end

  def handle_info(:refill, %{tokens: tokens_now} = state) do
    load = :cpu_sup.avg1() / 256 / (:erlang.system_info(:schedulers_online) / 2)
    Logger.info("Load: #{load}")
    new_tokens = calculate_tokens(load, state.slope, state.y_intercept)
    Logger.debug("New tokens: #{new_tokens}")
    tokens_next = tokens_now + new_tokens
    case tokens_next > @max_tokens do
      true ->
        {:noreply, %{state | tokens: @max_tokens}}
      false ->
        {:noreply, %{state | tokens: tokens_next}}
    end
  end

  defp calculate_tokens(load, slope, y_intercept) do
    new_tokens = slope * load + y_intercept
    Logger.debug("Calculated tokens: #{new_tokens}")
    cond do
      new_tokens > @max_refill_amount -> @max_refill_amount
      new_tokens > 0 -> trunc(new_tokens)
      true -> 0
    end
  end
end
