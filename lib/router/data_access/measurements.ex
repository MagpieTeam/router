defmodule Router.DataAccess.Measurements do
  import Router.DataAccess.Utils

  def put(measurements) do    
    {:ok, client} = :cqerl.new_client()
    # query = cql_query(
    #   statement: "INSERT INTO magpie.measurements (sensor_id, date, timestamp, metadata, value) VALUES (?, ?, ?, ?, ?);",
    #   values: [sensor_id: :uuid.string_to_uuid("586b3248-cb76-4941-ada9-fd8e9020ecef"), date: 1447977600000, timestamp: 1448022621000, metadata: "AAAF", value: {12005, 1}])
    query = cql_query(statement: "INSERT INTO magpie.measurements (sensor_id, date, timestamp, metadata, value) VALUES (?, ?, ?, ?, ?);")
    queries = for %{"sensor_id" => sensor_id, "timestamp" => timestamp, "metadata" => metadata, "value" => value} <- measurements do
      # TODO: Extract date from timestamp & Convert input string to decimal
      timestamp = String.to_integer(timestamp)
      date = div(timestamp, 10000) * 10000 # 1447977600000
      cql_query(query, values: [sensor_id: :uuid.string_to_uuid("925edb2b-2962-46b8-b24d-9395d832f374"), date: date, timestamp: timestamp, metadata: metadata, value: {value, 0}])
    end
    batch_query = cql_query_batch(mode: 1, consistency: 1, queries: queries)
    {:ok, result} = :cqerl.run_query(client, batch_query)
    # {:ok, result} = :cqerl.run_query(client, query)
    {:ok, measurements}
  end
  
end