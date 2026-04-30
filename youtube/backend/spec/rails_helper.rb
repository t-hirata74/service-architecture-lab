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

  # 共通: 外部 HTTP は WebMock でブロック (ai-worker への HTTP 呼び出しはスタブする)
  WebMock.disable_net_connect!(allow_localhost: true)

  config.filter_rails_from_backtrace!
end
