defmodule Gateway.Application do
  @moduledoc false

  use Application
  require Logger

  @impl true
  def start(_type, _args) do
    # Initialize Prometheus metrics
    Gateway.Metrics.setup()

    # Attach telemetry handlers
    Gateway.Telemetry.attach_handlers()

    # Start periodic metric updates
    start_metric_updater()

    children = [
      # PubSub for LiveView updates
      {Phoenix.PubSub, name: Gateway.PubSub},
      # DNS-based cluster discovery for Fly.io
      {DNSCluster, query: Application.get_env(:gateway, :dns_cluster_query) || :ignore},
      # Oban job processing
      {Oban, Application.fetch_env!(:gateway, Oban)},
      # Phoenix endpoint
      Gateway.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Gateway.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    Gateway.Endpoint.config_change(changed, removed)
    :ok
  end

  # ============================================================================
  # Private
  # ============================================================================

  defp start_metric_updater do
    # Update system metrics every 30 seconds
    spawn(fn ->
      Process.sleep(5_000)  # Wait 5 seconds for app to fully start
      update_metrics_loop()
    end)
  end

  defp update_metrics_loop do
    try do
      # Update system metrics from database
      image_stats = ImageStore.get_stats()
      Gateway.Metrics.update_system_metrics(%{
        total_count: image_stats.total_count,
        total_size_bytes: image_stats.total_size_bytes,
        pipeline_status_counts: image_stats.by_pipeline_status
      })

      # Update Oban queue metrics
      update_oban_metrics()

      # Update database pool metrics
      update_db_pool_metrics()
    rescue
      e ->
        Logger.warning("Failed to update metrics: #{inspect(e)}")
    end

    Process.sleep(30_000)  # Update every 30 seconds
    update_metrics_loop()
  end

  defp update_oban_metrics do
    # Get Oban queue stats by querying the database directly
    queues = Oban.config()[:queues] || []
    
    for {queue, _concurrency} <- queues do
      queue_name = to_string(queue)

      # Query Oban jobs from database
      try do
        import Ecto.Query
        repo = Oban.config()[:repo]

        # Count jobs by state
        available = repo.one(from j in Oban.Job, where: j.queue == ^queue_name and j.state == "available", select: count())
        scheduled = repo.one(from j in Oban.Job, where: j.queue == ^queue_name and j.state == "scheduled", select: count())
        executing = repo.one(from j in Oban.Job, where: j.queue == ^queue_name and j.state == "executing", select: count())

        Gateway.Metrics.update_oban_queue_metrics(queue_name, "available", available || 0)
        Gateway.Metrics.update_oban_queue_metrics(queue_name, "scheduled", scheduled || 0)
        Gateway.Metrics.update_oban_queue_metrics(queue_name, "executing", executing || 0)
      rescue
        e ->
          # If Oban.Job schema doesn't exist or query fails, skip
          Logger.debug("Failed to update Oban metrics for queue #{queue_name}: #{inspect(e)}")
          :ok
      end
    end
  end

  defp update_db_pool_metrics do
    # Get database pool stats
    pool_size = ImageStore.Repo.config()[:pool_size] || 10

    # Ecto doesn't expose pool stats directly, so we approximate
    # In production, you might want to query pg_stat_activity or use a pool monitoring library
    Gateway.Metrics.update_db_pool_metrics("image_store", pool_size, pool_size)
  end
end
