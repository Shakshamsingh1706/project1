# frozen_string_literal: true

server ENV["SERVER_IP"] || "127.0.0.1", user: "deploy", roles: %w[app db web]

set :stage, :production
