require "rails_helper"

RSpec.describe "GET /health", type: :request do
  it "returns ok with ai-worker status" do
    stub_request(:get, "http://localhost:8030/health")
      .to_return(status: 200, body: '{"status":"ok"}', headers: { "Content-Type" => "application/json" })

    get "/health"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["status"]).to eq("ok")
    expect(body["service"]).to eq("perplexity-backend")
    expect(body["ai_worker"]).to eq("ok")
  end

  it "reports degraded with ai_worker=unreachable when it cannot connect" do
    stub_request(:get, "http://localhost:8030/health").to_timeout

    get "/health"

    # 200 のまま、status を degraded に切り替えて LB が判断できるようにする
    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["status"]).to eq("degraded")
    expect(body["ai_worker"]).to eq("unreachable")
  end

  it "reports degraded when ai-worker returns 5xx" do
    stub_request(:get, "http://localhost:8030/health")
      .to_return(status: 500, body: "boom")

    get "/health"

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["status"]).to eq("degraded")
    expect(body["ai_worker"]).to eq("unreachable")
  end
end
