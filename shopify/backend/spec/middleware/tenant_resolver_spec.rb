require "rails_helper"

# ADR 0002: TenantResolver middleware の不変条件。
# - サブドメインから Shop が引ければ env に積む
# - 不明な subdomain は 404
# - サブドメイン無しは素通り (rodauth が tenant_unresolved で弾く)
# - `/up` は素通り
RSpec.describe Core::Middleware::TenantResolver do
  let(:inner) { ->(env) { [ 200, { "Content-Type" => "application/json" }, [ env["shopify.current_shop"]&.subdomain.to_s ] ] } }
  let(:middleware) { described_class.new(inner) }

  let!(:acme) { Core::Shop.create!(subdomain: "acme-store", name: "ACME") }
  let!(:globex) { Core::Shop.create!(subdomain: "globex", name: "Globex") }

  def call(host:, path: "/anything", header_subdomain: nil)
    env = Rack::MockRequest.env_for(path, "HTTP_HOST" => host)
    env["HTTP_X_SHOP_SUBDOMAIN"] = header_subdomain if header_subdomain
    middleware.call(env)
  end

  it "サブドメインから Shop を解決して env に積む" do
    status, _h, body = call(host: "acme-store.localhost:3090")
    expect(status).to eq(200)
    expect(body.first).to eq("acme-store")
  end

  it "別 Shop は別 Shop に解決される" do
    status, _h, body = call(host: "globex.localhost:3090")
    expect(status).to eq(200)
    expect(body.first).to eq("globex")
  end

  it "未登録の subdomain は 404" do
    status, _h, body = call(host: "ghost.localhost:3090")
    expect(status).to eq(404)
    expect(body.first).to include("tenant_not_found")
  end

  it "サブドメイン無しは素通り (current_shop は積まない)" do
    status, _h, body = call(host: "localhost:3090")
    expect(status).to eq(200)
    expect(body.first).to eq("")
  end

  it "/up は素通り (DB アクセスなし)" do
    status, _h, body = call(host: "ghost.localhost:3090", path: "/up")
    expect(status).to eq(200)
    expect(body.first).to eq("")
  end

  it "X-Shop-Subdomain header があればそれを優先 (テスト/dev 用)" do
    status, _h, body = call(host: "localhost:3090", header_subdomain: "acme-store")
    expect(status).to eq(200)
    expect(body.first).to eq("acme-store")
  end
end
