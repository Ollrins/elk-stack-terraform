resource "elasticstack_kibana_dashboard" "myapp_monitoring" {
  title            = "MyApp Monitoring"
  description      = "Dashboard for myapp logs (managed by Terraform)"
  time_range       = { from = "now-24h", to = "now" }
  refresh_interval = { pause = false, value = 30000 }
  query            = { language = "kql", expression = "" }

  panels = [
    # Панель 1: Data Table — распределение логов по уровню (INFO/WARN/ERROR)
    {
      type = "vis"
      grid = { x = 0, y = 0, w = 24, h = 15 }
      config_json = jsonencode({
        type = "data_table"
        data_source = {
          type          = "data_view_spec"
          index_pattern = "logs-*"
          time_field    = "@timestamp"
        }
        metrics = [{ operation = "count", label = "Total" }]
        rows = [{ operation = "terms", fields = ["level.keyword"], limit = 10 }]
        title = "Logs by level"
      })
    },

    # Панель 2: Data Table — ошибки в разрезе сервисов
    {
      type = "vis"
      grid = { x = 0, y = 15, w = 24, h = 15 }
      config_json = jsonencode({
        type = "data_table"
        data_source = {
          type          = "data_view_spec"
          index_pattern = "logs-*"
          time_field    = "@timestamp"
        }
        metrics = [{ operation = "count", label = "Errors" }]
        rows = [{ operation = "terms", fields = ["service.keyword"], limit = 10 }]
        query = { language = "kql", expression = "level: ERROR" }
        title = "Errors by service"
      })
    },

    # Панель 3: Data Table — топ-10 самых частых сообщений об ошибках
    {
      type = "vis"
      grid = { x = 0, y = 30, w = 24, h = 15 }
      config_json = jsonencode({
        type = "data_table"
        data_source = {
          type          = "data_view_spec"
          index_pattern = "logs-*"
          time_field    = "@timestamp"
        }
        metrics = [{ operation = "count", label = "Occurrences" }]
        rows = [{ operation = "terms", fields = ["message.keyword"], limit = 10 }]
        query = { language = "kql", expression = "level: ERROR" }
        title = "Top error messages"
      })
    }
  ]
}
