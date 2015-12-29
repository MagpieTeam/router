defmodule Router.LoadRegulator do
  use GenServer

  @max_tokens 1000
  @refill_interval 6000
  @refill_amount 100

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  def permit?() do
    GenServer.call(Router.LoadRegulator, :permit?)
  end

  def init(:ok) do
    :timer.send_interval(@refill_interval, :refill)

    {:ok, %{tokens: @max_tokens}}
  end

  def handle_call(:permit?, _from, %{tokens: tokens} = state) do
    case tokens > 0 do
      true -> {:reply, true, %{tokens: tokens - 1}}
      false -> {:reply, false, state}
    end
  end

  def handle_info(:refill, %{tokens: tokens_now}) do
    tokens_next = tokens_now + @refill_amount
    case tokens_next > @max_tokens do
      true ->
        {:noreply, %{tokens: @max_tokens}}
      false ->
        {:noreply, %{tokens: tokens_next}}
    end
  end
end
