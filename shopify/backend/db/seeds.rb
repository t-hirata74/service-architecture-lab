# Phase 1 (gif 用): demo データの idempotent 投入。
#
# 目的: ADR 0001-0004 を gif で示すための最小データを揃える。
#   - 2 shop (acme / globex) — multi-tenancy デモ用 (ADR 0002)
#   - 各 shop に商品 + variant + inventory_level
#   - 在庫 1 個の "限定品" — 並行 checkout デモ用 (ADR 0003)
#   - App + AppInstallation + WebhookSubscription (order_created → mock receiver) (ADR 0004)
#   - demo buyer (alice / bob) — playwright が register/login するので account 自体は作らない

require "securerandom"

mock_endpoint = ENV.fetch("MOCK_RECEIVER_URL", "http://localhost:4000/webhooks/shopify")

shops = [
  { subdomain: "acme",   name: "ACME Apparel" },
  { subdomain: "globex", name: "Globex Goods" }
].map do |attrs|
  Core::Shop.find_or_create_by!(subdomain: attrs[:subdomain]) { |s| s.name = attrs[:name] }
end

# 同一 slug "t-shirt" を両 shop に持たせ、ADR 0002 のテナント分離を視覚化できるようにする。
catalog_per_shop = {
  "acme" => [
    { slug: "t-shirt",       title: "ACME Logo Tee",         sku: "ACM-TEE-001", price: 2_400, on_hand: 25 },
    { slug: "mug",           title: "ACME Coffee Mug",       sku: "ACM-MUG-001", price: 1_500, on_hand: 40 },
    { slug: "limited-hoodie", title: "ACME Limited Hoodie", sku: "ACM-HOOD-LMT", price: 9_800, on_hand: 1  }  # ADR 0003
  ],
  "globex" => [
    { slug: "t-shirt",   title: "Globex Engineer Tee", sku: "GLX-TEE-001", price: 3_200, on_hand: 12 },
    { slug: "notebook",  title: "Globex Field Notebook", sku: "GLX-NB-001", price: 980,  on_hand: 60 }
  ]
}

shops.each do |shop|
  location = Inventory::Location.find_or_create_by!(shop: shop, name: "main") { |l| l.kind = "warehouse" }

  catalog_per_shop.fetch(shop.subdomain).each do |row|
    product = Catalog::Product.find_or_create_by!(shop: shop, slug: row[:slug]) do |p|
      p.title = row[:title]
      p.status = :active
    end
    # 既存 row の title を上書きしておく (再 seed 時のリネーム反映用)
    product.update!(title: row[:title], status: :active)

    variant = Catalog::Variant.find_or_create_by!(shop: shop, sku: row[:sku]) do |v|
      v.product = product
      v.price_cents = row[:price]
      v.currency = "JPY"
    end
    variant.update!(price_cents: row[:price])

    level = Inventory::InventoryLevel.find_or_create_by!(variant: variant, location: location) do |il|
      il.shop = shop
      il.on_hand = row[:on_hand]
    end
    # 在庫はデモ目的で毎回リセット (ADR 0003 の同時減算デモを再現できるように on_hand=1 に戻す)
    level.update!(on_hand: row[:on_hand])
  end
end

# ADR 0004: App + AppInstallation + WebhookSubscription
# secret は demo 用に固定 (env で上書き可能、HMAC 検証は固定 secret で一貫させる)
app = Apps::App.find_or_create_by!(name: "Demo Admin App") do |a|
  a.secret = ENV.fetch("DEMO_APP_SECRET", "demo-shared-secret-do-not-use-in-prod")
end
app.update!(secret: ENV.fetch("DEMO_APP_SECRET", "demo-shared-secret-do-not-use-in-prod"))

shops.each do |shop|
  raw_token = "demo-token-#{shop.subdomain}"
  digest = Apps::AppInstallation.digest_token(raw_token)

  installation = Apps::AppInstallation.find_or_create_by!(shop: shop, app: app) do |i|
    i.api_token_digest = digest
    i.scopes = "read_orders"
  end
  installation.update!(api_token_digest: digest, scopes: "read_orders")

  Apps::WebhookSubscription.find_or_create_by!(
    shop: shop,
    app_installation: installation,
    topic: "order_created"
  ) { |s| s.endpoint = mock_endpoint }.update!(endpoint: mock_endpoint)
end

# next_order_number は seed の度にリセットしない (運用想定: 番号は単調増加)
# が、開発時に order を全消ししても番号が飛ばないよう、orders が無いときだけ 1 に戻す。
shops.each do |shop|
  if Orders::Order.where(shop_id: shop.id).count.zero? && shop.next_order_number > 1
    shop.update!(next_order_number: 1)
  end
end

puts "[seed] shops:        #{shops.map(&:subdomain).join(', ')}"
puts "[seed] products:     #{Catalog::Product.count}"
puts "[seed] variants:     #{Catalog::Variant.count}"
puts "[seed] limited stock: ACM-HOOD-LMT on_hand=1 (ADR 0003 demo)"
puts "[seed] webhook subs: order_created → #{mock_endpoint}"
puts "[seed] api tokens:   demo-token-acme / demo-token-globex (Bearer)"
