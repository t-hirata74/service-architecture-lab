module Apps
  # 3rd-party App。secret は HMAC 鍵 (perinstall ではなく per-app)。
  class App < ApplicationRecord
    self.table_name = "apps_apps"

    has_many :installations, class_name: "Apps::AppInstallation", dependent: :destroy

    validates :name, presence: true, uniqueness: { case_sensitive: false }
    validates :secret, presence: true, length: { minimum: 16 }
  end
end
