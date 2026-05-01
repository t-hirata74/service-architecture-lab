require 'rails_helper'

RSpec.describe "Internal::CommitChecks", type: :request do
  let(:org)  { create(:organization, login: "acme") }
  let!(:repo) { create(:repository, organization: org, name: "tools") }
  let(:token) { "dev-internal-token" }

  def post_check(**payload)
    post "/internal/commit_checks",
         params: payload.to_json,
         headers: { "Content-Type" => "application/json", "X-Internal-Token" => token }
  end

  it "rejects without token" do
    post "/internal/commit_checks",
         params: { owner: "acme", name: "tools", head_sha: "abc", check_name: "build", state: "success" }.to_json,
         headers: { "Content-Type" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates a commit check (201)" do
    post_check(owner: "acme", name: "tools", head_sha: "abc", check_name: "build", state: "success", output: "ok")
    expect(response).to have_http_status(:created)
    json = JSON.parse(response.body)
    expect(json["state"]).to eq("success")
    expect(repo.commit_checks.where(head_sha: "abc", name: "build").count).to eq(1)
  end

  it "upserts on second call for same (repo, sha, name)" do
    post_check(owner: "acme", name: "tools", head_sha: "abc", check_name: "build", state: "pending")
    post_check(owner: "acme", name: "tools", head_sha: "abc", check_name: "build", state: "failure", output: "boom")
    rows = repo.commit_checks.where(head_sha: "abc", name: "build")
    expect(rows.count).to eq(1)
    expect(rows.first.state).to eq("failure")
    expect(rows.first.output).to eq("boom")
  end

  it "404 when repository not found" do
    post_check(owner: "acme", name: "ghost", head_sha: "abc", check_name: "x", state: "success")
    expect(response).to have_http_status(:not_found)
  end

  it "422 on unknown state" do
    post_check(owner: "acme", name: "tools", head_sha: "abc", check_name: "build", state: "weird")
    expect(response).to have_http_status(:unprocessable_content)
  end
end
