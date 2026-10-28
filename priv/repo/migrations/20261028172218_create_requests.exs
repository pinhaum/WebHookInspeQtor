defmodule Whiq.Repo.Migrations.CreateRequests do
  use Ecto.Migration

  def change do
    create table(:requests) do
      add :bin_id, references(:bins, on_delete: :delete_all), null: false
      add :method, :text, null: false
      add :path, :text, null: false
      add :query_string, :text, null: false
      add :headers, {:array, :binary}, null: false
      add :body, :binary, null: false
      add :body_size, :integer, null: false
      add :content_type, :binary
      add :remote_ip, :text, null: false

      timestamps(type: :utc_datetime_usec, updated_at: false)
    end

    create index(:requests, [:bin_id, :inserted_at])
  end
end
