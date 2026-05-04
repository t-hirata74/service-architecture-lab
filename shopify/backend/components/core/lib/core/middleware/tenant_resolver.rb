module Core
  module Middleware
    # ADR 0002: リクエストの Host サブドメインから Shop を解決し、`shopify.current_shop` に詰める。
    #
    # サブドメイン解決対象パスの判定:
    #   - `/up`, `/rails/*` (health) は素通り
    #   - `/apps/api/*` (3rd-party App API) も素通り — Apps::Api::BaseController が
    #     `Authorization: Bearer <token>` から AppInstallation 経由で shop を解決する
    #   - `/create-account`, `/login`, `/logout` 等の rodauth パスはサブドメイン必須 (登録時に shop が決まる)
    #
    # 解決方針:
    #   - `acme-store.localhost` → "acme-store"
    #   - `localhost` (サブドメイン無し) → 解決しない (rack env に積まない)
    #   - 不明な subdomain → 404 を返す (controller が引いた時に TenantNotFound)
    #
    # フォールバック (テスト/開発用): `X-Shop-Subdomain` ヘッダがあればそれを優先。
    class TenantResolver
      SKIP_PATHS = %r{\A/(up|rails/|apps/api/)}

      def initialize(app)
        @app = app
      end

      def call(env)
        return @app.call(env) if env["PATH_INFO"]&.match?(SKIP_PATHS)

        subdomain = extract_subdomain(env)
        if subdomain
          shop = Core::Shop.find_by(subdomain: subdomain)
          if shop
            env["shopify.current_shop"] = shop
          else
            return [ 404, { "Content-Type" => "application/json" }, [ %({"error":"tenant_not_found"}) ] ]
          end
        end

        @app.call(env)
      end

      private

      def extract_subdomain(env)
        header_override = env["HTTP_X_SHOP_SUBDOMAIN"]
        return header_override if header_override.present?

        host = env["HTTP_HOST"].to_s.split(":").first.to_s.downcase
        return nil if host.empty?

        parts = host.split(".")
        # `acme-store.localhost` → ["acme-store", "localhost"] → 先頭を採用
        # `localhost` → ["localhost"] → サブドメイン無し
        return nil if parts.size < 2

        sub = parts.first
        # `www` のような generic prefix は除外 (本プロジェクトでは使わない)
        sub == "www" ? nil : sub
      end
    end
  end
end
