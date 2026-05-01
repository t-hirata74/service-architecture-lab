require 'spec_helper'
ENV['RAILS_ENV'] ||= 'test'
require_relative '../config/environment'
abort("The Rails environment is running in production mode!") if Rails.env.production?
require 'rspec/rails'
require 'webmock/rspec'

begin
  ActiveRecord::Migration.maintain_test_schema!
rescue ActiveRecord::PendingMigrationError => e
  abort e.to_s.strip
end

RSpec.configure do |config|
  config.use_transactional_fixtures = true

  # FactoryBot のショートハンド (`create(:video)` 等) を使えるようにする
  config.include FactoryBot::Syntax::Methods

  # ActiveJob テストヘルパ (have_enqueued_job 等)
  config.include ActiveJob::TestHelper, type: :model
  config.include ActiveJob::TestHelper, type: :request
  config.include ActiveJob::TestHelper, type: :job

  # travel_to / freeze_time 等
  config.include ActiveSupport::Testing::TimeHelpers

  # OpenAPI 契約検証: request spec で `assert_schema_conform(status)` を呼べる
  # ようになる (docs/api-style.md / docs/openapi.yml)
  config.add_setting :committee_options
  config.committee_options = {
    schema_path: Rails.root.join("docs", "openapi.yml").to_s,
    strict_reference_validation: false,
    parse_response_by_content_type: false,
    # 学習用 (form-encoded / JSON / multipart どれも許容): リクエスト検証は緩く、
    # レスポンス契約だけ厳密に守る。
    check_content_type: false,
    check_header: false
  }
  config.include Committee::Rails::Test::Methods, type: :request

  # 共通: 外部 HTTP は WebMock でブロック (ai-worker への HTTP 呼び出しはスタブする)
  WebMock.disable_net_connect!(allow_localhost: true)

  config.filter_rails_from_backtrace!
end
