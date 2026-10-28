defmodule Whiq.Repo.Migrations.CreateBins do
  use Ecto.Migration

  def change do
    create table(:bins) do
      add :capture_token, :string, null: false
      add :view_token, :string, null: false
      add :expires_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:bins, [:capture_token])
    create unique_index(:bins, [:view_token])
  end
end
