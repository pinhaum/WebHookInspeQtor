defmodule WhiqWeb.ByteFormat do
  @moduledoc """
  Turns sender-controlled bytes into display-safe UTF-8 strings. LiveView
  encodes diffs as JSON, which rejects invalid UTF-8, so every captured
  byte passes through here before it reaches a template.
  """

  @doc """
  Classifies a body for display: empty, valid UTF-8 text, or a hex dump of
  every byte when any part of it is not valid UTF-8.
  """
  def body(""), do: :empty

  def body(body) when is_binary(body) do
    if String.valid?(body), do: {:text, body}, else: {:hex, hex_dump(body)}
  end

  @doc """
  One line per 16 bytes: an 8-digit hex offset, two spaces, then the bytes
  as lowercase hex pairs separated by spaces.
  """
  def hex_dump(bytes) when is_binary(bytes) do
    bytes
    |> :binary.bin_to_list()
    |> Enum.chunk_every(16)
    |> Enum.with_index()
    |> Enum.map_join("\n", fn {line, index} ->
      offset =
        (index * 16) |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(8, "0")

      offset <> "  " <> Enum.map_join(line, " ", &hex_byte/1)
    end)
  end

  @doc """
  Keeps valid UTF-8 as is and replaces each byte of an invalid run with
  `\\xNN`. `nil` becomes `""`.
  """
  def printable(nil), do: ""

  def printable(bytes) when is_binary(bytes) do
    bytes
    |> String.chunk(:valid)
    |> Enum.map_join(fn chunk ->
      if String.valid?(chunk) do
        chunk
      else
        for <<byte <- chunk>>, into: "", do: "\\x" <> hex_byte(byte)
      end
    end)
  end

  defp hex_byte(byte), do: Base.encode16(<<byte>>, case: :lower)
end
