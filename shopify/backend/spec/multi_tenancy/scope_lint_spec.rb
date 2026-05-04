require "rails_helper"

# ADR 0002: 「全 tenant-scoped model が `TenantOwned` concern を include しているか」を CI で固定する。
# このリストは Phase 3 以降の増加に合わせて更新する (Product / InventoryLevel / Order ...)。
RSpec.describe "Tenant-owned models lint" do
  TENANT_OWNED_MODELS = [
    Core::User,
    Catalog::Product,
    Catalog::Variant,
    Inventory::Location,
    Inventory::InventoryLevel,
    Inventory::StockMovement
    # Phase 4+: Orders::Order, Orders::LineItem, Apps::AppInstallation, ...
  ].freeze

  TENANT_OWNED_MODELS.each do |klass|
    it "#{klass.name} は TenantOwned を include している" do
      expect(klass.included_modules).to include(TenantOwned)
    end
  end
end
