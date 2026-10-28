defmodule Whiq.Inspector.CapturedRequest do
  @moduledoc """
  One request captured by a bin, stored byte-exact. Headers are a flat
  `[name1, value1, name2, value2, ...]` list in received order (AD-008).
  Every field is set by `Whiq.Inspector`, so the schema has no changeset.
  """
  use Ecto.Schema

  schema "requests" do
    belongs_to :bin, Whiq.Inspector.Bin
    field :method, :string
    field :path, :string
    field :query_string, :string
    field :headers, {:array, :binary}
    field :body, :binary
    field :body_size, :integer
    field :content_type, :binary
    field :remote_ip, :string

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end
end
