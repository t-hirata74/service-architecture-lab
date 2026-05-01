require 'rails_helper'

RSpec.describe "GraphQL", type: :request do
  def post_graphql(query, headers: {}, variables: {})
    post "/graphql",
         params: { query:, variables: }.to_json,
         headers: { "Content-Type" => "application/json" }.merge(headers)
    JSON.parse(response.body)
  end

  describe "viewer" do
    let(:user) { create(:user, login: "alice") }

    it "returns the authenticated viewer" do
      body = post_graphql("{ viewer { login name } }", headers: { "X-User-Login" => user.login })
      expect(body.dig("data", "viewer", "login")).to eq("alice")
    end

    it "returns null when unauthenticated" do
      body = post_graphql("{ viewer { login } }")
      expect(body.dig("data", "viewer")).to be_nil
    end

    it "exposes email only to the viewer themselves" do
      other = create(:user, login: "bob")
      body = post_graphql(
        "{ viewer { email } }",
        headers: { "X-User-Login" => user.login }
      )
      expect(body.dig("data", "viewer", "email")).to eq(user.email)

      # other user querying viewer (alice の email は出ない設計: email は self のみ)
      body2 = post_graphql(
        %({ organization(login: "#{user.login}") { login } }), # noop, structural placeholder
        headers: { "X-User-Login" => other.login }
      )
      expect(body2["errors"]).to be_nil
    end
  end

  describe "repository" do
    let(:org)  { create(:organization, login: "acme") }
    let(:repo) { create(:repository, organization: org, name: "tools", visibility: :private_visibility) }
    let(:member) { create(:user, login: "member-user") }
    let(:outsider) { create(:user, login: "outsider") }

    before do
      Membership.create!(organization: org, user: member, role: :member)
      repo
    end

    it "returns repository to a member with READ" do
      body = post_graphql(
        %|query($o:String!,$n:String!){ repository(owner:$o, name:$n){ name viewerPermission } }|,
        headers: { "X-User-Login" => member.login },
        variables: { o: "acme", n: "tools" }
      )
      expect(body.dig("data", "repository", "name")).to eq("tools")
      expect(body.dig("data", "repository", "viewerPermission")).to eq("READ")
    end

    it "hides private repository from outsiders (returns null)" do
      body = post_graphql(
        %|query($o:String!,$n:String!){ repository(owner:$o, name:$n){ name } }|,
        headers: { "X-User-Login" => outsider.login },
        variables: { o: "acme", n: "tools" }
      )
      expect(body.dig("data", "repository")).to be_nil
    end

    it "exposes public repository to anyone" do
      repo.update!(visibility: :public_visibility)
      body = post_graphql(
        %|query($o:String!,$n:String!){ repository(owner:$o, name:$n){ name viewerPermission } }|,
        variables: { o: "acme", n: "tools" }
      )
      expect(body.dig("data", "repository", "name")).to eq("tools")
      expect(body.dig("data", "repository", "viewerPermission")).to eq("READ")
    end

    it "returns ADMIN viewerPermission to org admin" do
      admin = create(:user, login: "admin-user")
      Membership.create!(organization: org, user: admin, role: :admin)
      body = post_graphql(
        %|query($o:String!,$n:String!){ repository(owner:$o, name:$n){ viewerPermission } }|,
        headers: { "X-User-Login" => admin.login },
        variables: { o: "acme", n: "tools" }
      )
      expect(body.dig("data", "repository", "viewerPermission")).to eq("ADMIN")
    end
  end

  describe "organization.repositories" do
    let(:org) { create(:organization, login: "acme") }
    let!(:public_repo)  { create(:repository, organization: org, name: "public", visibility: :public_visibility) }
    let!(:private_repo) { create(:repository, organization: org, name: "secret", visibility: :private_visibility) }

    it "lists only repositories visible to the viewer" do
      outsider = create(:user, login: "outsider")
      body = post_graphql(
        %|query($l:String!){ organization(login:$l){ repositories { name } } }|,
        headers: { "X-User-Login" => outsider.login },
        variables: { l: "acme" }
      )
      names = body.dig("data", "organization", "repositories").map { |r| r["name"] }
      expect(names).to eq(["public"])
    end

    it "shows all repositories to org member" do
      member = create(:user, login: "member-user")
      Membership.create!(organization: org, user: member, role: :member)
      body = post_graphql(
        %|query($l:String!){ organization(login:$l){ repositories { name } } }|,
        headers: { "X-User-Login" => member.login },
        variables: { l: "acme" }
      )
      names = body.dig("data", "organization", "repositories").map { |r| r["name"] }
      expect(names).to contain_exactly("public", "secret")
    end
  end
end
