defmodule Whiq.Repo.Migrations.AddExpiresAtIndexToBins do
  use Ecto.Migration

  # CONCURRENTLY keeps bins writable during the build; Postgres rejects it
  # inside a transaction, and Ecto's default migration lock is one.
  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create index(:bins, [:expires_at], concurrently: true)
  end
end
