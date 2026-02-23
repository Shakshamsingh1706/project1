# frozen_string_literal: true

Rails.application.routes.draw do
  Spree::Core::Engine.add_routes do
    devise_for(
      Spree.admin_user_class.model_name.singular_route_key,
      class_name: Spree.admin_user_class.to_s,
      controllers: {
        sessions: "spree/admin/user_sessions",
        passwords: "spree/admin/user_passwords"
      },
      skip: :registrations,
      path: :admin_user,
      router_name: :spree
    )
  end

  mount Spree::Core::Engine, at: "/"
  devise_for :admin_users, class_name: "Spree::AdminUser"
  devise_for :users, class_name: "Spree::User"

  get "up" => "rails/health#show", as: :rails_health_check
end
