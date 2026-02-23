# frozen_string_literal: true

require_relative "boot"

require "rails"
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

# Load .env when present (e.g. shared/.env on server)
app_root = File.expand_path("..", __dir__)
env_file = File.join(app_root, ".env")
if File.exist?(env_file)
  require "dotenv"
  Dotenv.load(env_file)
end

module StorefrontApp
  class Application < Rails::Application
    config.load_defaults 8.1
    config.autoload_lib(ignore: %w[assets tasks])
    config.generators.system_tests = nil

    config.to_prepare do
      Dir.glob(Rails.root.join("app/**/*_decorator*.rb")).each do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end
  end
end
