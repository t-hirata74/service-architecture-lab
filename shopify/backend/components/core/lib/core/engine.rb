require "core/middleware/tenant_resolver"

module Core
  class Engine < ::Rails::Engine
    isolate_namespace Core

    # rodauth-rails の middleware は `before_create_account` 等の hook 内で
    # `request.env["shopify.current_shop"]` を読む。Rodauth より前に走らせる必要がある。
    initializer "core.tenant_resolver", after: :load_config_initializers do |app|
      app.middleware.insert_before Rodauth::Rails::Middleware, Core::Middleware::TenantResolver
    end
  end
end
