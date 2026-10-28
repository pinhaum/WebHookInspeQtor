defmodule Whiq.Inspector.Bin do
  @moduledoc """
  A bin receives requests at its public `capture_token` and is read only
  through its private `view_token` (AD-005). Every field is set by
  `Whiq.Inspector`, so the schema has no changeset.
  """
  use Ecto.Schema

  schema "bins" do
    field :capture_token, :string
    field :view_token, :string
    field :expires_at, :utc_datetime

    has_many :requests, Whiq.Inspector.CapturedRequest

    timestamps(type: :utc_datetime, updated_at: false)
  end
end
