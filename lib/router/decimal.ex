defmodule Router.Decimal do

  def from_string(value) when is_binary(value) do
    case String.split(value, ".") do
      [integer, remainder] ->
        scale = byte_size(remainder)
        {String.to_integer(integer <> remainder), scale}
      [integer] ->
        {String.to_integer(integer), 0}
    end
  end

  def to_string({unscaled, scale}) when unscaled < 0 do
    abs = Router.Decimal.to_string({abs(unscaled), scale})
    "-" <> abs
  end

  def to_string({unscaled, scale}) do
    unscaled_string = Integer.to_string(unscaled)
    digits = byte_size(unscaled_string)

    case digits - scale do
      x when is_integer(x) and x > 1 ->
        << integer :: binary - size(x), remainder :: binary >> = unscaled_string
        integer <> "." <> remainder
      0 -> "0." <> unscaled_string
      x when is_integer(x) and x < 1 ->
        "0." <> String.duplicate("0", abs(x)) <> unscaled_string
    end
  end

end