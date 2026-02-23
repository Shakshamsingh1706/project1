# frozen_string_literal: true

# Spree preferences and dependencies (required before routes)
Spree.config do |config|
  config.disable_migration_check = true
end

Spree.user_class = "Spree::User"
Spree.admin_user_class = "Spree::AdminUser"

Rails.application.config.to_prepare do
  require "spree/authentication_helpers"
end

if defined?(Devise) && Devise.respond_to?(:parent_controller)
  Devise.parent_controller = "Spree::BaseController"
end

Rails.application.config.after_initialize do
  Spree.permissions.assign(:default, [Spree::PermissionSets::DefaultCustomer])
  Spree.permissions.assign(:admin, [Spree::PermissionSets::SuperUser])
end
