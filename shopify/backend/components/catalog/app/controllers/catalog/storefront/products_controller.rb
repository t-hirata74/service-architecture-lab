module Catalog
  module Storefront
    # Storefront 公開 API: ログイン不要で active な Product 一覧を返す。
    # ADR 0002: current_shop は middleware が確定済み。
    class ProductsController < ::ApplicationController
      def index
        # ADR 0002: 明示 scope (current_shop.id) を必ず通す。Core::Shop に has_many :products を
        # 持たせると core が catalog に逆依存してしまうので、ここでは明示 scope のみ。
        products = Catalog::Product.where(shop_id: current_shop.id, status: Catalog::Product.statuses[:active])
                                   .order(created_at: :desc)

        render json: products.map { |p| serialize_product(p) }
      end

      def show
        product = Catalog::Product.where(shop_id: current_shop.id, slug: params[:slug]).first!
        render json: serialize_product(product, include_variants: true)
      end

      private

      def serialize_product(product, include_variants: false)
        h = { id: product.id, slug: product.slug, title: product.title, description: product.description, status: product.status }
        if include_variants
          h[:variants] = product.variants.map { |v| { id: v.id, sku: v.sku, price_cents: v.price_cents, currency: v.currency } }
        end
        h
      end
    end
  end
end
