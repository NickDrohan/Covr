defmodule ImageStore.Repo do
  use Ecto.Repo,
    otp_app: :image_store,
    adapter: Ecto.Adapters.Postgres
end
