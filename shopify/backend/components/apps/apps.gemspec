Gem::Specification.new do |spec|
  spec.name        = "apps"
  spec.version     = "0.1.0"
  spec.authors     = ["shopify-lab"]
  spec.summary     = "apps component (Rails Engine, modular monolith — ADR 0001)"
  spec.files       = Dir["app/**/*", "config/**/*", "db/**/*", "lib/**/*"]
  spec.required_ruby_version = ">= 3.3.0"
  spec.add_dependency "rails", "~> 8.1.3"
end
