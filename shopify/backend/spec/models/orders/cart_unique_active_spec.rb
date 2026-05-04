require "rails_helper"

# Review fix C2: orders_carts UNIQUE 制約により、customer ごとに open cart は 1 つだけ。
# completed/abandoned は何個でも持てる (active_marker IS NULL なので UNIQUE をすり抜ける)。
RSpec.describe Orders::Cart do
  let(:shop) { Core::Shop.create!(subdomain: "uacme", name: "ACME") }
  let(:customer) { Core::User.create!(shop: shop, email: "buyer@example.com") }

  it "同一 customer の 2 つ目の open cart は UNIQUE 違反で弾かれる" do
    Orders::Cart.create!(shop: shop, customer: customer, status: :open)

    expect {
      Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it "completed cart は何個でも持てる (active_marker が NULL)" do
    3.times { Orders::Cart.create!(shop: shop, customer: customer, status: :completed) }
    expect(Orders::Cart.where(shop: shop, customer: customer, status: :completed).count).to eq(3)
  end

  it "open → completed に遷移したら同 customer は別の open cart を作れる" do
    cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    cart.update!(status: :completed)
    expect(cart.reload.active_marker).to be_nil

    new_cart = Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    expect(new_cart.active_marker).to eq(1)
  end

  it "別 shop の同 email customer の open cart とは衝突しない" do
    other_shop = Core::Shop.create!(subdomain: "other", name: "Other")
    other_customer = Core::User.create!(shop: other_shop, email: "buyer@example.com")

    Orders::Cart.create!(shop: shop, customer: customer, status: :open)
    expect {
      Orders::Cart.create!(shop: other_shop, customer: other_customer, status: :open)
    }.not_to raise_error
  end
end
