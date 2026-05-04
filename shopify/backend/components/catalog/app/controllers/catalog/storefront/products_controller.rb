module Catalog
  module Storefront
    # Storefront 公開 API: ログイン不要で active な Product 一覧を返す。
    # ADR 0002: current_shop は middleware が確定済み。
    class ProductsController < ::ApplicationController
      # M7: enum scope syntax を使う (`.active`)。`statuses[:active]` の数値直書きより読みやすい。
      def index
        # ADR 0002: 明示 scope (current_shop.id) を必ず通す。Core::Shop に has_many :products を
        # 持たせると core が catalog に逆依存してしまうので、ここでは明示 scope のみ。
        products = Catalog::Product.where(shop_id: current_shop.id).active.order(created_at: :desc)

        render json: products.map { |p| serialize_product(p) }
      end

      def show
        product = Catalog::Product.where(shop_id: current_shop.id, slug: params[:slug])
                                  .includes(:variants).first!
        render json: serialize_product(product, include_variants: true)
      end

      # M8: ai-worker 統合のデモ。
      # GET /storefront/products/:slug/recommendations
      # 同 shop の他 active product から ai-worker /recommend で deterministic に並べ替えて返す。
      # ai-worker 未起動時は空配列で graceful degradation (perplexity ADR 0005 と同じ運用パターン)。
      def recommendations
        product = Catalog::Product.where(shop_id: current_shop.id, slug: params[:slug]).first!
        candidates = Catalog::Product.where(shop_id: current_shop.id).active.where.not(id: product.id).pluck(:id)

        result = Catalog::AiWorkerClient.recommend(
          shop_id: current_shop.id, product_id: product.id,
          candidate_product_ids: candidates, limit: 5
        )
        related_ids = result["related"]
        related_products = Catalog::Product.where(shop_id: current_shop.id, id: related_ids).index_by(&:id)
        ordered = related_ids.map { |id| related_products[id] }.compact

        render json: { product_id: product.id, related: ordered.map { |p| serialize_product(p) } }
      rescue Catalog::AiWorkerClient::Error => e
        Rails.logger.warn("[catalog] ai-worker unavailable: #{e.message}")
        render json: { product_id: product.id, related: [], degraded: true }
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
