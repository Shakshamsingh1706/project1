# frozen_string_literal: true

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.cache_classes = true

  config.consider_all_requests_local = false
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = true
  config.public_file_server.headers = { "cache-control" => "public, max-age=#{1.year.to_i}" }

  # Assets: do not compile at runtime (precompile during deploy)
  config.assets.compile = false
  config.assets.js_compressor = nil
  config.assets.css_compressor = nil

  config.active_storage.service = :local
  config.log_level = :info
  config.log_tags = [:request_id]
  config.logger = ActiveSupport::TaggedLogging.logger($stdout)
  config.silence_healthcheck_path = "/up"
  config.active_support.report_deprecations = false

  config.cache_store = :memory_store
  config.active_job.queue_adapter = :async

  config.action_mailer.raise_delivery_errors = false
  config.action_mailer.default_url_options = { host: ENV.fetch("APP_HOST", "localhost") }

  config.i18n.fallbacks = true
  config.active_record.dump_schema_after_migration = false
end
