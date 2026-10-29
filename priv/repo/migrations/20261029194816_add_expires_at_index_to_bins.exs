defmodule Whiq.Repo.Migrations.AddExpiresAtIndexToBins do
  use Ecto.Migration

  def change do
    create index(:bins, [:expires_at])
  end
end
