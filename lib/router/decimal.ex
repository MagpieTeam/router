defmodule Router.Decimal do

  def from_string(value) when is_binary(value) do
    String.split(value, ".")
    case Regex.named_captures(~r/^(?<integer>\d*)\.?(?<rest>\d*)$/, value) do
      %{"integer" => integer, "rest" => rest} -> 
        scale = String.length(rest)
        {String.to_integer(integer <> rest), scale}
      %{"integer" => integer, "rest" => ""} ->
        {String.to_integer(integer), 0}
    end
  end
  
end