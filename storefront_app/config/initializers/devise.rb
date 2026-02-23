# frozen_string_literal: true

# Minimal Devise setup so that User/AdminUser models can use the devise method.
# Required: require ORM so ActiveRecord gets the .devise class method.
require "devise/orm/active_record"

Devise.setup do |config|
  config.mailer_sender = "please-change-me-at-config-initializers-devise@example.com"
end
