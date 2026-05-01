require 'rails_helper'

# ADR 0001 が掲げた "N+1 を graphql-batch (Dataloader) で潰す" を実装と spec で固定する。
#
# 計測方針:
# - 5 件の repository を持つ org に対して `organization.repositories { viewerPermission }` を実行
# - viewer_permission の解決クエリ本数が **repo 数に比例しない** ことを確認
RSpec.describe "GraphQL N+1 (viewerPermission)", type: :request do
  let(:org)   { create(:organization, login: "acme") }
  let(:user)  { create(:user, login: "alice") }
  let!(:repos) { 5.times.map { |i| create(:repository, organization: org, name: "repo-#{i}") } }

  before do
    Membership.create!(organization: org, user: user, role: :member)
    # 1 つだけ collaborator role 上書き (loader が collaborator も batch することを確認するため)
    RepositoryCollaborator.create!(repository: repos.first, user: user, role: :write)
  end

  def count_queries
    queries = []
    callback = ->(_, _, _, _, payload) {
      sql = payload[:sql]
      next if sql =~ /\A(SAVEPOINT|RELEASE|BEGIN|COMMIT|ROLLBACK|SHOW |PRAGMA )/i
      next if payload[:name] == "SCHEMA"
      queries << sql
    }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end
    queries
  end

  it "resolves viewer_permission for N repositories with constant DB queries" do
    query = <<~GQL
      { organization(login:"acme") { repositories { name viewerPermission } } }
    GQL

    queries = count_queries do
      result = BackendSchema.execute(query, context: { current_user: user })
      perms = result["data"]["organization"]["repositories"].map { |r| r["viewerPermission"] }
      expect(perms).to all(eq("READ").or eq("WRITE"))
    end

    # 期待値: organization 解決 1 + repositories 解決 1 + viewer-perm batch 系 (membership / team_member / team_repo / collab) ≤ 6
    # 純粋 N+1 だと repo 5 件 × 4 クエリ = 20 を超える。閾値 10 で確実に区別できる。
    expect(queries.size).to be <= 10
  end
end
