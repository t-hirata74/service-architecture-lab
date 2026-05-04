module Apps
  module Api
    # 3rd-party App 経由の API 入口の base controller。
    # `Authorization: Bearer <api_token>` を AppInstallation#api_token_digest と照合し、
    # current_shop は installation の shop に固定する (subdomain 由来の current_shop は無視)。
    #
    # ADR 0004: scope-based 認可。各 action の `requires_scope!` でチェックする。
    class BaseController < ::ApplicationController
      class InvalidAppToken < StandardError; end
      class MissingScope < StandardError
        attr_reader :scope
        def initialize(scope) = (@scope = scope; super("missing scope: #{scope}"))
      end

      rescue_from InvalidAppToken do
        render json: { error: "invalid_app_token" }, status: :unauthorized
      end
      rescue_from MissingScope do |e|
        render json: { error: "missing_scope", scope: e.scope }, status: :forbidden
      end

      before_action :authenticate_app_installation!

      attr_reader :current_app_installation

      # Apps API は subdomain ではなく api_token から shop を解決する。
      def current_shop
        current_app_installation.shop
      end

      private

      def authenticate_app_installation!
        token = bearer_token
        raise InvalidAppToken if token.blank?

        digest = Apps::AppInstallation.digest_token(token)
        @current_app_installation = Apps::AppInstallation.find_by(api_token_digest: digest)
        raise InvalidAppToken if @current_app_installation.nil?
      end

      def bearer_token
        header = request.headers["Authorization"].to_s
        header[/\ABearer\s+(.+)\z/, 1]
      end

      def requires_scope!(scope)
        raise MissingScope.new(scope) unless current_app_installation.has_scope?(scope)
      end
    end
  end
end
