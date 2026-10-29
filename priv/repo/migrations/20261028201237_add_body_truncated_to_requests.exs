defmodule Whiq.Repo.Migrations.AddBodyTruncatedToRequests do
  use Ecto.Migration

  def change do
    alter table(:requests) do
      add :body_truncated, :boolean, null: false, default: false
    end
  end
end
