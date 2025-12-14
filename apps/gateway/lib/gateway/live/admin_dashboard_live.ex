defmodule Gateway.AdminDashboardLive do
  @moduledoc """
  LiveView for the admin dashboard.
  Displays real-time database stats, pipeline jobs, and API endpoints.
  """

  use Phoenix.LiveView, layout: {Gateway.Layouts, :app}

  @refresh_interval 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe to pipeline updates
      Phoenix.PubSub.subscribe(Gateway.PubSub, "pipeline:updates")
      # Schedule periodic refresh
      schedule_refresh()
    end

    {:ok, load_data(socket)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    schedule_refresh()
    {:noreply, load_data(socket)}
  end

  @impl true
  def handle_info({:pipeline_update, _update}, socket) do
    # Reload data when a pipeline completes
    {:noreply, load_data(socket)}
  end

  defp schedule_refresh do
    Process.send_after(self(), :refresh, @refresh_interval)
  end

  defp load_data(socket) do
    image_stats = ImageStore.get_stats()
    pipeline_stats = ImageStore.Pipeline.get_stats()
    recent_executions = ImageStore.Pipeline.list_executions(limit: 10)

    socket
    |> assign(:image_stats, image_stats)
    |> assign(:pipeline_stats, pipeline_stats)
    |> assign(:recent_executions, recent_executions)
    |> assign(:last_updated, DateTime.utc_now())
  end

  @impl true
  def render(assigns) do
    ~H"""
    <!-- Database Stats Section -->
    <section class="mb-4">
      <h2 class="section-title">Database Statistics</h2>
      <div class="grid grid-4">
        <div class="card">
          <div class="stat-value"><%= @image_stats.total_count %></div>
          <div class="stat-label">Total Images</div>
        </div>
        <div class="card">
          <div class="stat-value"><%= @image_stats.total_size_mb %> MB</div>
          <div class="stat-label">Total Storage</div>
        </div>
        <div class="card">
          <div class="stat-value"><%= @image_stats.avg_size_kb %> KB</div>
          <div class="stat-label">Avg Image Size</div>
        </div>
        <div class="card">
          <div class="stat-value"><%= @image_stats.recent_uploads_24h %></div>
          <div class="stat-label">Uploads (24h)</div>
        </div>
      </div>
    </section>

    <!-- Images by Kind -->
    <section class="mb-4">
      <div class="grid grid-2">
        <div class="card">
          <div class="card-header">
            <span class="card-title">Images by Kind</span>
          </div>
          <table>
            <thead>
              <tr>
                <th>Kind</th>
                <th>Count</th>
              </tr>
            </thead>
            <tbody>
              <%= if map_size(@image_stats.by_kind) > 0 do %>
                <%= for {kind, count} <- @image_stats.by_kind do %>
                  <tr>
                    <td><%= kind %></td>
                    <td><%= count %></td>
                  </tr>
                <% end %>
              <% else %>
                <tr>
                  <td colspan="2" class="empty-state">No images yet</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>

        <div class="card">
          <div class="card-header">
            <span class="card-title">Pipeline Status Distribution</span>
          </div>
          <table>
            <thead>
              <tr>
                <th>Status</th>
                <th>Count</th>
              </tr>
            </thead>
            <tbody>
              <%= if map_size(@image_stats.by_pipeline_status) > 0 do %>
                <%= for {status, count} <- @image_stats.by_pipeline_status do %>
                  <tr>
                    <td><span class={"badge badge-#{status}"}><%= status %></span></td>
                    <td><%= count %></td>
                  </tr>
                <% end %>
              <% else %>
                <tr>
                  <td colspan="2" class="empty-state">No data</td>
                </tr>
              <% end %>
            </tbody>
          </table>
        </div>
      </div>
    </section>

    <!-- Pipeline Stats Section -->
    <section class="mb-4">
      <h2 class="section-title">Pipeline Statistics</h2>
      <div class="grid grid-4">
        <div class="card">
          <div class="stat-value"><%= @pipeline_stats.pending %></div>
          <div class="stat-label">Pending Jobs</div>
        </div>
        <div class="card">
          <div class="stat-value"><%= @pipeline_stats.running %></div>
          <div class="stat-label">Running Jobs</div>
        </div>
        <div class="card">
          <div class="stat-value text-success"><%= @pipeline_stats.success_rate %>%</div>
          <div class="stat-label">Success Rate</div>
          <div class="progress-bar mt-2">
            <div class="progress-fill" style={"width: #{@pipeline_stats.success_rate}%"}></div>
          </div>
        </div>
        <div class="card">
          <div class="stat-value"><%= format_duration(@pipeline_stats.avg_duration_ms) %></div>
          <div class="stat-label">Avg Duration</div>
        </div>
      </div>
    </section>

    <!-- Recent Executions -->
    <section class="mb-4">
      <h2 class="section-title">Recent Pipeline Executions</h2>
      <div class="card">
        <table>
          <thead>
            <tr>
              <th>Execution ID</th>
              <th>Image ID</th>
              <th>Status</th>
              <th>Started</th>
              <th>Duration</th>
              <th>Steps</th>
            </tr>
          </thead>
          <tbody>
            <%= if length(@recent_executions) > 0 do %>
              <%= for exec <- @recent_executions do %>
                <tr>
                  <td class="text-muted" style="font-family: monospace; font-size: 0.75rem;">
                    <%= short_id(exec.id) %>
                  </td>
                  <td class="text-muted" style="font-family: monospace; font-size: 0.75rem;">
                    <%= short_id(exec.image_id) %>
                  </td>
                  <td>
                    <span class={"badge badge-#{exec.status}"}><%= exec.status %></span>
                  </td>
                  <td class="text-muted"><%= format_time(exec.started_at) %></td>
                  <td><%= format_execution_duration(exec) %></td>
                  <td>
                    <div class="flex gap-2">
                      <%= for step <- exec.steps do %>
                        <span class={"badge badge-#{step.status}"} title={step.step_name}>
                          <%= step_icon(step.step_name) %>
                        </span>
                      <% end %>
                    </div>
                  </td>
                </tr>
              <% end %>
            <% else %>
              <tr>
                <td colspan="6" class="empty-state">No pipeline executions yet</td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>
    </section>

    <!-- API Endpoints Section -->
    <section class="mb-4">
      <h2 class="section-title">API Endpoints</h2>
      <div class="card">
        <table>
          <thead>
            <tr>
              <th>Method</th>
              <th>Endpoint</th>
              <th>Description</th>
            </tr>
          </thead>
          <tbody>
            <tr>
              <td><span class="method method-post">POST</span></td>
              <td class="api-endpoint">/api/images</td>
              <td>Upload a new image (multipart/form-data)</td>
            </tr>
            <tr>
              <td><span class="method method-get">GET</span></td>
              <td class="api-endpoint">/api/images/:id</td>
              <td>Get image metadata</td>
            </tr>
            <tr>
              <td><span class="method method-get">GET</span></td>
              <td class="api-endpoint">/api/images/:id/blob</td>
              <td>Download image binary</td>
            </tr>
            <tr>
              <td><span class="method method-get">GET</span></td>
              <td class="api-endpoint">/api/images/:id/pipeline</td>
              <td>Get pipeline status and results</td>
            </tr>
            <tr>
              <td><span class="method method-get">GET</span></td>
              <td class="api-endpoint">/images</td>
              <td>List all images</td>
            </tr>
            <tr>
              <td><span class="method method-get">GET</span></td>
              <td class="api-endpoint">/healthz</td>
              <td>Health check</td>
            </tr>
          </tbody>
        </table>
      </div>
    </section>

    <!-- Last Updated -->
    <div class="text-muted" style="text-align: center; font-size: 0.75rem;">
      Last updated: <%= format_time(@last_updated) %>
    </div>
    """
  end

  # ============================================================================
  # Helper Functions
  # ============================================================================

  defp short_id(nil), do: "-"
  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8) <> "..."

  defp format_time(nil), do: "-"
  defp format_time(datetime) do
    Calendar.strftime(datetime, "%H:%M:%S")
  end

  defp format_duration(0), do: "-"
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"
  defp format_duration(ms), do: "#{Float.round(ms / 1000, 1)}s"

  defp format_execution_duration(%{started_at: nil}), do: "-"
  defp format_execution_duration(%{completed_at: nil, started_at: started_at}) do
    elapsed = DateTime.diff(DateTime.utc_now(), started_at, :millisecond)
    format_duration(elapsed) <> "..."
  end
  defp format_execution_duration(%{started_at: started_at, completed_at: completed_at}) do
    duration = DateTime.diff(completed_at, started_at, :millisecond)
    format_duration(duration)
  end

  defp step_icon("book_identification"), do: "ID"
  defp step_icon("image_cropping"), do: "CR"
  defp step_icon("health_assessment"), do: "HA"
  defp step_icon(_), do: "?"
end
