require 'rails_helper'

RSpec.describe "GraphQL addComment", type: :request do
  def post_graphql(query, headers: {}, variables: {})
    post "/graphql",
         params: { query:, variables: }.to_json,
         headers: { "Content-Type" => "application/json" }.merge(headers)
    JSON.parse(response.body)
  end

  let(:org)      { create(:organization) }
  let(:repo)     { create(:repository, organization: org, visibility: :private_visibility) }
  let(:member)   { create(:user, login: "member-user") }
  let(:outsider) { create(:user, login: "outsider") }
  let(:issue)    { create(:issue, repository: repo, author: member) }

  before do
    Membership.create!(organization: org, user: member, role: :member)
  end

  let(:mutation) do
    %|mutation($id:ID!,$b:String!){
        addComment(input:{ issueId:$id, body:$b }){ comment{ body author{ login } } errors }
      }|
  end

  it "lets a member comment" do
    body = post_graphql(mutation, headers: { "X-User-Login" => member.login },
                                  variables: { id: issue.id.to_s, b: "lgtm" })
    expect(body.dig("data", "addComment", "comment", "body")).to eq("lgtm")
    expect(body.dig("data", "addComment", "comment", "author", "login")).to eq("member-user")
    expect(body.dig("data", "addComment", "errors")).to eq([])
  end

  it "rejects outsider on private repo" do
    body = post_graphql(mutation, headers: { "X-User-Login" => outsider.login },
                                  variables: { id: issue.id.to_s, b: "x" })
    expect(body.dig("data", "addComment", "comment")).to be_nil
    expect(body.dig("data", "addComment", "errors")).to eq(["Forbidden"])
  end

  it "rejects unauthenticated" do
    body = post_graphql(mutation, variables: { id: issue.id.to_s, b: "x" })
    expect(body["errors"].first["message"]).to eq("Unauthenticated")
  end

  it "404 when issue missing" do
    body = post_graphql(mutation, headers: { "X-User-Login" => member.login },
                                  variables: { id: "999999", b: "x" })
    expect(body.dig("data", "addComment", "errors")).to eq(["Issue not found"])
  end

  it "validation error for empty body" do
    body = post_graphql(mutation, headers: { "X-User-Login" => member.login },
                                  variables: { id: issue.id.to_s, b: "" })
    expect(body.dig("data", "addComment", "comment")).to be_nil
    expect(body.dig("data", "addComment", "errors")).to include(/Body/)
  end
end
