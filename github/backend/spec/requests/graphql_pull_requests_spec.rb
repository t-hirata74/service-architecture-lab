require 'rails_helper'

RSpec.describe "GraphQL pull requests / mutations", type: :request do
  def post_graphql(query, headers: {}, variables: {})
    post "/graphql",
         params: { query:, variables: }.to_json,
         headers: { "Content-Type" => "application/json" }.merge(headers)
    JSON.parse(response.body)
  end

  let(:org)      { create(:organization, login: "acme") }
  let(:repo)     { create(:repository, organization: org, name: "tools", visibility: :private_visibility) }
  let(:author)   { create(:user, login: "author-user") }
  let(:writer)   { create(:user, login: "writer") }
  let(:maintain) { create(:user, login: "maintainer") }
  let(:reviewer) { create(:user, login: "reviewer-user") }

  before do
    Membership.create!(organization: org, user: author, role: :member)
    Membership.create!(organization: org, user: writer, role: :member)
    Membership.create!(organization: org, user: maintain, role: :member)
    Membership.create!(organization: org, user: reviewer, role: :member)
    RepositoryCollaborator.create!(repository: repo, user: writer, role: :write)
    RepositoryCollaborator.create!(repository: repo, user: maintain, role: :maintain)
    RepositoryCollaborator.create!(repository: repo, user: reviewer, role: :write)
  end

  describe "createPullRequest" do
    let(:mutation) do
      <<~GQL
        mutation($o:String!,$n:String!,$t:String!,$h:String!,$b:String,$sha:String!){
          createPullRequest(input:{ owner:$o, name:$n, title:$t, headRef:$h, body:$b, headSha:$sha }) {
            pullRequest { number title state mergeableState headRef baseRef author { login } }
            errors
          }
        }
      GQL
    end

    it "creates a PR via shared number space (ADR 0003)" do
      # まず Issue を 1 件作って番号 1 を取る
      Issue.create!(repository: repo, author: author, title: "first issue",
                    body: "", number: IssueNumberAllocator.next_for(repo), state: :open)

      body = post_graphql(
        mutation,
        headers: { "X-User-Login" => author.login },
        variables: { o: "acme", n: "tools", t: "Add feature", h: "feature/x", b: "summary", sha: "abc123" }
      )
      pr = body.dig("data", "createPullRequest", "pullRequest")
      expect(body.dig("data", "createPullRequest", "errors")).to eq([])
      expect(pr["number"]).to eq(2) # Issue が 1 を取った後の続き
      expect(pr["state"]).to eq("OPEN")
      expect(pr["mergeableState"]).to eq("MERGEABLE")
      expect(pr["author"]["login"]).to eq("author-user")
    end

    it "rejects unauthenticated requests" do
      body = post_graphql(
        mutation,
        variables: { o: "acme", n: "tools", t: "x", h: "h", b: "", sha: "s" }
      )
      expect(body["errors"].first["message"]).to eq("Unauthenticated")
    end
  end

  describe "requestReview" do
    let!(:pr) do
      create(:pull_request, repository: repo, author: author,
                            number: IssueNumberAllocator.next_for(repo))
    end

    it "lets a writer add reviewers" do
      body = post_graphql(
        %|mutation($id:ID!,$logins:[String!]!){
            requestReview(input:{ pullRequestId:$id, reviewerLogins:$logins }) {
              pullRequest{ requestedReviewers{ login } } errors
            }
          }|,
        headers: { "X-User-Login" => writer.login },
        variables: { id: pr.id.to_s, logins: [reviewer.login] }
      )
      logins = body.dig("data", "requestReview", "pullRequest", "requestedReviewers").map { |u| u["login"] }
      expect(logins).to contain_exactly("reviewer-user")
    end

    it "denies a plain member without write" do
      plain = create(:user, login: "plain")
      Membership.create!(organization: org, user: plain, role: :member)
      body = post_graphql(
        %|mutation($id:ID!,$logins:[String!]!){ requestReview(input:{ pullRequestId:$id, reviewerLogins:$logins }) { errors } }|,
        headers: { "X-User-Login" => plain.login },
        variables: { id: pr.id.to_s, logins: [reviewer.login] }
      )
      expect(body.dig("data", "requestReview", "errors")).to eq(["Forbidden"])
    end
  end

  describe "submitReview" do
    let!(:pr) do
      pr = create(:pull_request, repository: repo, author: author,
                                 number: IssueNumberAllocator.next_for(repo))
      pr.requested_reviewers.create!(user: reviewer)
      pr
    end

    it "creates a review and removes the reviewer from requested list" do
      body = post_graphql(
        %|mutation($id:ID!,$s:ReviewState!,$b:String){
            submitReview(input:{ pullRequestId:$id, state:$s, body:$b }) {
              review{ state body reviewer{ login } } errors
            }
          }|,
        headers: { "X-User-Login" => reviewer.login },
        variables: { id: pr.id.to_s, s: "APPROVED", b: "lgtm" }
      )
      review = body.dig("data", "submitReview", "review")
      expect(review["state"]).to eq("APPROVED")
      expect(review["body"]).to eq("lgtm")
      expect(review["reviewer"]["login"]).to eq("reviewer-user")
      expect(pr.reload.requested_reviewers.where(user_id: reviewer.id)).to be_empty
    end
  end

  describe "mergePullRequest" do
    let!(:pr) do
      create(:pull_request, repository: repo, author: author,
                            number: IssueNumberAllocator.next_for(repo))
    end

    it "merges when caller has maintain" do
      body = post_graphql(
        %|mutation($id:ID!){ mergePullRequest(input:{ pullRequestId:$id }){ pullRequest{ state mergeableState } errors } }|,
        headers: { "X-User-Login" => maintain.login },
        variables: { id: pr.id.to_s }
      )
      result = body.dig("data", "mergePullRequest", "pullRequest")
      expect(result["state"]).to eq("MERGED")
      expect(result["mergeableState"]).to eq("MERGED")
    end

    it "denies write-only callers" do
      body = post_graphql(
        %|mutation($id:ID!){ mergePullRequest(input:{ pullRequestId:$id }){ errors } }|,
        headers: { "X-User-Login" => writer.login },
        variables: { id: pr.id.to_s }
      )
      expect(body.dig("data", "mergePullRequest", "errors")).to eq(["Forbidden"])
    end

    it "rejects merge on conflict" do
      pr.update!(mergeable_state: :conflict)
      body = post_graphql(
        %|mutation($id:ID!){ mergePullRequest(input:{ pullRequestId:$id }){ errors } }|,
        headers: { "X-User-Login" => maintain.login },
        variables: { id: pr.id.to_s }
      )
      errors = body.dig("data", "mergePullRequest", "errors")
      expect(errors.first).to match(/not mergeable/)
      expect(pr.reload.state).to eq("open")
    end
  end

  describe "repository.pullRequests / pullRequest query" do
    let!(:pr1) do
      create(:pull_request, repository: repo, author: author, state: :open,
                            number: IssueNumberAllocator.next_for(repo), title: "p1")
    end
    let!(:pr2) do
      create(:pull_request, repository: repo, author: author, state: :merged,
                            number: IssueNumberAllocator.next_for(repo), title: "p2")
    end

    it "lists pull requests newest first" do
      body = post_graphql(
        %|{ repository(owner:"acme", name:"tools"){ pullRequests { number title state } } }|,
        headers: { "X-User-Login" => author.login }
      )
      numbers = body.dig("data", "repository", "pullRequests").map { |p| p["number"] }
      expect(numbers).to eq([pr2.number, pr1.number])
    end

    it "filters by state" do
      body = post_graphql(
        %|{ repository(owner:"acme", name:"tools"){ pullRequests(state: MERGED) { number state } } }|,
        headers: { "X-User-Login" => author.login }
      )
      states = body.dig("data", "repository", "pullRequests").map { |p| p["state"] }
      expect(states).to all(eq("MERGED"))
    end

    it "fetches single PR by number with reviews" do
      pr1.reviews.create!(reviewer: reviewer, state: :approved, body: "lgtm")
      body = post_graphql(
        %|query($n:Int!){ pullRequest(owner:"acme", name:"tools", number:$n){ title reviews{ state reviewer{ login } } } }|,
        headers: { "X-User-Login" => author.login },
        variables: { n: pr1.number }
      )
      result = body.dig("data", "pullRequest")
      expect(result["title"]).to eq("p1")
      expect(result["reviews"].first["state"]).to eq("APPROVED")
      expect(result["reviews"].first["reviewer"]["login"]).to eq("reviewer-user")
    end
  end

  describe "Issue / PR shared number space" do
    it "uses the same allocator counter (ADR 0003)" do
      n1 = IssueNumberAllocator.next_for(repo)
      Issue.create!(repository: repo, author: author, title: "x", body: "", number: n1, state: :open)

      n2 = IssueNumberAllocator.next_for(repo)
      pr = create(:pull_request, repository: repo, author: author, number: n2)

      expect(n2).to eq(n1 + 1)
      expect(pr.number).to eq(n2)
    end
  end
end
