ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
require "committee/rails/test/methods"

module ActiveSupport
  class TestCase
    # Run tests in parallel with specified workers
    parallelize(workers: :number_of_processors)

    # Setup all fixtures in test/fixtures/*.yml for all tests in alphabetical order.
    fixtures :all
  end
end

# OpenAPI 契約検証: ActionDispatch::IntegrationTest で `assert_schema_conform(status)` を
# 呼べるようにする (docs/api-style.md / docs/openapi.yml)
class ActionDispatch::IntegrationTest
  include Committee::Rails::Test::Methods

  def committee_options
    @committee_options ||= {
      schema_path: Rails.root.join("docs", "openapi.yml").to_s,
      strict_reference_validation: false,
      parse_response_by_content_type: false,
      check_content_type: false,
      check_header: false
    }
  end
end
