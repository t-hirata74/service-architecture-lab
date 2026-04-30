class RodauthController < ApplicationController
  # rodauth 自身のエンドポイント (login/create-account/logout 等) は認証前に呼ばれるため、
  # ApplicationController の before_action :authenticate! を skip する必要がある。
  skip_before_action :authenticate!

  # Layout can be changed for all Rodauth pages or only certain pages.
  # layout "authentication"
  # layout -> do
  #   case rodauth.current_route
  #   when :login, :create_account, :verify_account, :verify_account_resend,
  #        :reset_password, :reset_password_request
  #     "authentication"
  #   else
  #     "application"
  #   end
  # end
end
