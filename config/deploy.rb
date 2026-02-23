# frozen_string_literal: true

lock "~> 3.20"

set :application, "spree"
set :repo_url, "https://github.com/spree/spree.git"
set :branch, :main
set :deploy_to, "/var/www/spree"
set :keep_releases, 5
set :pty, true

# Rails app lives in server/
set :app_path, "server"
set :bundle_gemfile, -> { File.join(release_path, fetch(:app_path), "Gemfile") }
set :rails_env, :production

# Ruby 3.2.2 via rbenv
set :rbenv_type, :user
set :rbenv_ruby, "3.2.2"
set :rbenv_map_bins, %w[rake gem bundle ruby rails puma pumactl]

# Shared dirs: server log + public/system; Puma uses shared/tmp via config
set :linked_dirs, fetch(:linked_dirs, []).push(
  "server/log",
  "server/public/system"
)

# Linked files
set :linked_files, fetch(:linked_files, []).push(
  "server/config/database.yml",
  "server/config/master.key"
)

set :format, :pretty
set :log_level, :debug

namespace :deploy do
  after :migrate, :create_shared_dirs
  after :publishing, :restart

  task :create_shared_dirs do
    on release_roles(:app) do
      execute :mkdir, "-p", shared_path.join("tmp/sockets"), shared_path.join("tmp/pids"), shared_path.join("log")
      execute :mkdir, "-p", shared_path.join("server/log")
    end
  end

  task :restart do
    invoke "puma:restart"
  end
end

# Commands run from server/
SSHKit.config.command_map[:rake]  = "bundle exec rake"
SSHKit.config.command_map[:rails] = "bundle exec rails"

namespace :bundler do
  task :install do
    on release_roles(:all) do
      within release_path.join(fetch(:app_path)) do
        execute :bundle, :install, "--without development test", "--deployment", "--quiet"
      end
    end
  end
end

Rake::Task["deploy:migrate"].clear if Rake::Task.task_defined?("deploy:migrate")
namespace :deploy do
  task :migrate do
    on release_roles(:db) do
      within release_path.join(fetch(:app_path)) do
        with rails_env: fetch(:rails_env) do
          execute :rake, "db:migrate"
        end
      end
    end
  end
end

Rake::Task["deploy:assets:precompile"].clear if Rake::Task.task_defined?("deploy:assets:precompile")
namespace :deploy do
  namespace :assets do
    task :precompile do
      on release_roles(:app) do
        within release_path.join(fetch(:app_path)) do
          with rails_env: fetch(:rails_env) do
            execute :rake, "assets:precompile"
          end
        end
      end
    end
  end
end
