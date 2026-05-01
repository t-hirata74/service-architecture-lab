require 'rails_helper'

RSpec.describe "PullRequest#aggregated_check_state" do
  let(:repo) { create(:repository) }
  let(:pr)   { create(:pull_request, repository: repo, head_sha: "abc") }

  it "returns 'none' when no checks exist" do
    expect(pr.aggregated_check_state).to eq("none")
  end

  it "returns 'success' when all checks succeed" do
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :success)
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "test",  state: :success)
    expect(pr.aggregated_check_state).to eq("success")
  end

  it "returns 'failure' when any check fails" do
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :success)
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "test",  state: :failure)
    expect(pr.aggregated_check_state).to eq("failure")
  end

  it "returns 'failure' when error is present (treated as red)" do
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :error)
    expect(pr.aggregated_check_state).to eq("failure")
  end

  it "returns 'pending' when at least one is still pending and none failed" do
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :success)
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "test",  state: :pending)
    expect(pr.aggregated_check_state).to eq("pending")
  end

  it "ignores checks scoped to other head_sha" do
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :success)
    CommitCheck.upsert_check!(repository: repo, head_sha: "xyz", name: "build", state: :failure)
    expect(pr.aggregated_check_state).to eq("success")
  end

  it "upsert overwrites prior state for same (repo, sha, name)" do
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :pending)
    CommitCheck.upsert_check!(repository: repo, head_sha: "abc", name: "build", state: :success)
    expect(repo.commit_checks.where(head_sha: "abc", name: "build").count).to eq(1)
    expect(pr.aggregated_check_state).to eq("success")
  end
end
