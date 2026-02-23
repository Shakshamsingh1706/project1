namespace :puma do
  task :restart do
    on roles(:app) do
      execute :sudo, :systemctl, :restart, :spree
    end
  end
end
