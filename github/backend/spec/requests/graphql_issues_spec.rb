require 'rails_helper'

RSpec.describe "GraphQL issues / mutations", type: :request do
  def post_graphql(query, headers: {}, variables: {})
    post "/graphql",
         params: { query:, variables: }.to_json,
         headers: { "Content-Type" => "application/json" }.merge(headers)
    JSON.parse(response.body)
  end

  let(:org) { create(:organization, login: "acme") }
  let(:repo) { create(:repository, organization: org, name: "tools", visibility: :private_visibility) }
  let(:member) { create(:user, login: "member-user") }
  let(:triager) { create(:user, login: "triager") }
  let(:outsider) { create(:user, login: "outsider") }

  before do
    Membership.create!(organization: org, user: member, role: :member)
    Membership.create!(organization: org, user: triager, role: :member)
    RepositoryCollaborator.create!(repository: repo, user: triager, role: :triage)
  end

  describe "createIssue" do
    let(:mutation) do
      <<~GQL
        mutation($o:String!,$n:String!,$t:String!,$b:String){
          createIssue(input:{ owner:$o, name:$n, title:$t, body:$b }) {
            issue { number title body author { login } state }
            errors
          }
        }
      GQL
    end

    it "creates an issue with allocated number when viewer has read" do
      body = post_graphql(
        mutation,
        headers: { "X-User-Login" => member.login },
        variables: { o: "acme", n: "tools", t: "First", b: "hello" }
      )
      issue = body.dig("data", "createIssue", "issue")
      expect(body.dig("data", "createIssue", "errors")).to eq([])
      expect(issue["number"]).to eq(1)
      expect(issue["title"]).to eq("First")
      expect(issue["author"]["login"]).to eq("member-user")
      expect(issue["state"]).to eq("OPEN")
    end

    it "increments numbers within the same repository" do
      [%w[A], %w[B], %w[C]].each do |(t)|
        post_graphql(mutation,
                     headers: { "X-User-Login" => member.login },
                     variables: { o: "acme", n: "tools", t: t, b: "" })
      end
      expect(repo.issues.order(:number).pluck(:number)).to eq([1, 2, 3])
    end

    it "rejects unauthenticated requests" do
      body = post_graphql(
        mutation,
        variables: { o: "acme", n: "tools", t: "X", b: "" }
      )
      expect(body["errors"].first["message"]).to eq("Unauthenticated")
    end

    it "rejects outsider on private repository" do
      body = post_graphql(
        mutation,
        headers: { "X-User-Login" => outsider.login },
        variables: { o: "acme", n: "tools", t: "X", b: "" }
      )
      expect(body.dig("data", "createIssue", "errors")).to eq(["Forbidden"])
      expect(body.dig("data", "createIssue", "issue")).to be_nil
    end
  end

  describe "closeIssue" do
    it "lets a triager close" do
      issue = create(:issue, repository: repo, author: member)
      body = post_graphql(
        "mutation($id:ID!){ closeIssue(input:{ issueId:$id }){ issue{ state } errors } }",
        headers: { "X-User-Login" => triager.login },
        variables: { id: issue.id.to_s }
      )
      expect(body.dig("data", "closeIssue", "issue", "state")).to eq("CLOSED")
    end

    it "denies a plain member without triage" do
      issue = create(:issue, repository: repo, author: member)
      body = post_graphql(
        "mutation($id:ID!){ closeIssue(input:{ issueId:$id }){ issue { state } errors } }",
        headers: { "X-User-Login" => member.login },
        variables: { id: issue.id.to_s }
      )
      expect(body.dig("data", "closeIssue", "errors")).to eq(["Forbidden"])
      expect(body.dig("data", "closeIssue", "issue")).to be_nil
    end
  end

  describe "assignIssue" do
    it "replaces assignees and triage role can assign" do
      issue = create(:issue, repository: repo, author: member)
      another = create(:user, login: "another")
      body = post_graphql(
        %|mutation($id:ID!,$logins:[String!]!){ assignIssue(input:{ issueId:$id, assigneeLogins:$logins }){ issue{ assignees{ login } } errors } }|,
        headers: { "X-User-Login" => triager.login },
        variables: { id: issue.id.to_s, logins: [member.login, another.login] }
      )
      logins = body.dig("data", "assignIssue", "issue", "assignees").map { |u| u["login"] }
      expect(logins).to contain_exactly("member-user", "another")
    end
  end

  describe "addComment" do
    it "lets a member comment on an open issue" do
      issue = create(:issue, repository: repo, author: triager)
      body = post_graphql(
        "mutation($id:ID!,$b:String!){ addComment(input:{ issueId:$id, body:$b }){ comment{ body author{ login } } errors } }",
        headers: { "X-User-Login" => member.login },
        variables: { id: issue.id.to_s, b: "looks good" }
      )
      comment = body.dig("data", "addComment", "comment")
      expect(comment["body"]).to eq("looks good")
      expect(comment["author"]["login"]).to eq("member-user")
    end
  end

  describe "repository.issues / issue query" do
    let!(:i1) { create(:issue, repository: repo, author: member, number: 1, state: :open,   title: "first") }
    let!(:i2) { create(:issue, repository: repo, author: member, number: 2, state: :closed, title: "second") }
    let!(:i3) { create(:issue, repository: repo, author: member, number: 3, state: :open,   title: "third") }

    it "lists issues newest first" do
      body = post_graphql(
        %|{ repository(owner:"acme", name:"tools"){ issues { number title state } } }|,
        headers: { "X-User-Login" => member.login }
      )
      numbers = body.dig("data", "repository", "issues").map { |i| i["number"] }
      expect(numbers).to eq([3, 2, 1])
    end

    it "filters by state" do
      body = post_graphql(
        %|{ repository(owner:"acme", name:"tools"){ issues(state: OPEN) { number state } } }|,
        headers: { "X-User-Login" => member.login }
      )
      states = body.dig("data", "repository", "issues").map { |i| i["state"] }
      expect(states).to all(eq("OPEN"))
      expect(body.dig("data", "repository", "issues").size).to eq(2)
    end

    it "fetches single issue by number with comments + author" do
      i1.comments.create!(author: triager, body: "first comment")
      body = post_graphql(
        %|{ issue(owner:"acme", name:"tools", number: 1){ title comments{ body author{ login } } } }|,
        headers: { "X-User-Login" => member.login }
      )
      issue = body.dig("data", "issue")
      expect(issue["title"]).to eq("first")
      expect(issue["comments"].first["body"]).to eq("first comment")
      expect(issue["comments"].first["author"]["login"]).to eq("triager")
    end

    it "hides issue from non-readers" do
      body = post_graphql(
        %|{ issue(owner:"acme", name:"tools", number: 1){ title } }|,
        headers: { "X-User-Login" => outsider.login }
      )
      expect(body.dig("data", "issue")).to be_nil
    end
  end
end
