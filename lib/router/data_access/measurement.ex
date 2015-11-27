defmodule Router.DataAccess.Measurement do
  import Router.DataAccess.Util

  def put(measurements) do
    {:ok, client} = :cqerl.new_client()
    query = cql_query(statement: "INSERT INTO magpie.measurements (sensor_id, date, timestamp, metadata, value) VALUES (?, ?, ?, ?, ?);")
    queries = for %{"sensor_id" => sensor_id, "timestamp" => timestamp, "metadata" => metadata, "value" => value} <- measurements do
      timestamp = String.to_integer(timestamp)
      date =
        timestamp
        |> Kernel.*(1000)
        |> Timex.Date.from(:us)
        |> Timex.Date.set([hour: 0, minute: 0, second: 0, ms: 0, validate: false])
        |> Timex.DateFormat.format!("{s-epoch}")
        |> String.to_integer()
        |> Kernel.*(1000)
      {value, _} = Float.parse(value)
      cql_query(query, values: [sensor_id: :uuid.string_to_uuid(sensor_id), date: date, timestamp: timestamp, metadata: metadata, value: value])
    end
    batch_query = cql_query_batch(mode: 1, consistency: 1, queries: queries)
    {:ok, result} = :cqerl.run_query(client, batch_query)
    {:ok, measurements}
  end
end