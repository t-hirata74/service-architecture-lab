# rodauth がレンダリング時に流用する Rails コントローラ.
# API モードのため ActionController::API を継承する (slack/backend と同じパターン).
class RodauthController < ActionController::API
end
