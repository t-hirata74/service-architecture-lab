require "rails_helper"

# ADR 0001: packwerk による依存方向違反が 0 件であることを RSpec で fixate する。
# bin/packwerk check と同じことを spec として走らせ、CI ログより読みやすい形で残す。
RSpec.describe "Modular monolith — packwerk dependency direction" do
  it "packwerk check で violations が 0 件" do
    output = `cd #{Rails.root} && bin/packwerk check 2>&1`
    expect($?.success?).to be(true), "packwerk check failed:\n#{output}"
    expect(output).to include("No offenses detected")
  end
end
