defmodule Router.DataAccess.Utils do
  require Record
  Record.defrecord(:cql_query, Record.extract(:cql_query, from: "deps/cqerl/include/cqerl.hrl"))
  Record.defrecord(:cql_query_batch, Record.extract(:cql_query_batch, from: "deps/cqerl/include/cqerl.hrl"))
end