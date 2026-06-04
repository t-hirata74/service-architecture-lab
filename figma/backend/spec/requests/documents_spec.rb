require "rails_helper"

# ADR 0002/0004: documents REST (作成 / 一覧 / snapshot / catch-up / member 追加 + 認可)。
RSpec.describe "Documents", type: :request do
  def create_document(headers, name: "My Doc")
    post "/documents", params: { name: }.to_json, headers: headers
    JSON.parse(response.body)
  end

  it "作成すると owner member になり、一覧・snapshot が引ける" do
    _alice, h = signup(email: "alice@example.com", name: "Alice")

    doc = create_document(h)
    expect(response).to have_http_status(:created)
    expect(doc["role"]).to eq("owner")
    expect(doc["version"]).to eq(0)

    get "/documents", headers: h
    expect(JSON.parse(response.body).map { |d| d["id"] }).to include(doc["id"])

    get "/documents/#{doc['id']}", headers: h
    body = JSON.parse(response.body)
    expect(body["version"]).to eq(0)
    expect(body["objects"]).to eq([])
  end

  it "snapshot は alive な materialized object を返し、catch-up は seq>since の op を返す" do
    alice, h = signup(email: "alice2@example.com", name: "Alice")
    doc = create_document(h)
    document = Document.find(doc["id"])

    OperationApplier.call(document:, actor: alice, shape_id: "A", op_type: "create",
                          payload: { "kind" => "rect", "x" => 5 }, lamport: 1)
    OperationApplier.call(document:, actor: alice, shape_id: "A", op_type: "update",
                          payload: { "x" => 9 }, lamport: 2)

    get "/documents/#{doc['id']}", headers: h
    body = JSON.parse(response.body)
    expect(body["version"]).to eq(2)
    expect(body["objects"].first["props"]).to eq("x" => 9)

    get "/documents/#{doc['id']}/operations", params: { since: 1 }, headers: h
    ops = JSON.parse(response.body)
    expect(ops.map { |o| o["seq"] }).to eq([ 2 ])
  end

  it "非 member は snapshot 取得不可 (403)" do
    _alice, ha = signup(email: "owner@example.com")
    doc = create_document(ha)
    _bob, hb = signup(email: "bob@example.com")

    get "/documents/#{doc['id']}", headers: hb
    expect(response).to have_http_status(:forbidden)
  end

  it "auto-layout proxy は member の現在 object を ai-worker に渡し結果を返す" do
    alice, h = signup(email: "layout@example.com")
    doc = create_document(h)
    document = Document.find(doc["id"])
    OperationApplier.call(document:, actor: alice, shape_id: "A", op_type: "create",
                          payload: { "kind" => "rect", "x" => 13, "y" => 0, "w" => 8, "h" => 8 }, lamport: 1)

    # ai-worker はテストでは stub (内部 ingress の配線のみ検証)。
    allow(AiWorkerClient).to receive(:auto_layout)
      .and_return("mode" => "align-left", "updates" => [ { "id" => "A", "x" => 0, "y" => 0 } ])

    post "/documents/#{doc['id']}/auto_layout", params: { mode: "align-left" }.to_json, headers: h
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["updates"].first["id"]).to eq("A")
  end

  it "owner は member を追加でき、非 owner は 403" do
    alice, ha = signup(email: "o2@example.com")
    bob, _hb = signup(email: "b2@example.com")
    carol, hc = signup(email: "c2@example.com")
    doc = create_document(ha)

    post "/documents/#{doc['id']}/members",
         params: { user_id: bob.id, role: "editor" }.to_json, headers: ha
    expect(response).to have_http_status(:created)
    expect(Document.find(doc["id"]).member_role(bob.id)).to eq("editor")

    # carol(非 member) は追加できない
    post "/documents/#{doc['id']}/members",
         params: { user_id: carol.id, role: "editor" }.to_json, headers: hc
    expect(response).to have_http_status(:forbidden)
  end
end
