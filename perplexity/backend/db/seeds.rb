# Phase 2: 5 件のローカルドキュメントを投入し、ai-worker 経由で chunk + embedding を生成する.
#
# 実行: bundle exec rails db:seed
# 前提: ai-worker が :8030 で起動していること。

require "net/http"

def ai_worker_alive?(base_url)
  uri = URI.parse("#{base_url}/health")
  response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1.0, read_timeout: 1.0) do |http|
    http.get(uri.path)
  end
  response.is_a?(Net::HTTPSuccess)
rescue StandardError
  false
end

ai_worker_url = ENV.fetch("AI_WORKER_URL", "http://localhost:8030")
unless ai_worker_alive?(ai_worker_url)
  warn "[seeds] ai-worker が起動していません (#{ai_worker_url}/health)"
  warn "        別タブで `cd perplexity/ai-worker && uvicorn main:app --port 8030` を起動してください"
  exit 1
end

SEED_DOCUMENTS = [
  {
    title: "東京タワーの概要",
    url: "https://example.local/tokyo-tower",
    body: <<~TXT
      東京タワーは、東京都港区芝公園に立地する高さ 333 メートルの総合電波塔である。
      1958 年に完成し、当時は世界一高い自立式鉄塔として知られていた。

      展望台は地上 150 メートルと 250 メートルにあり、東京周辺を一望できる。
      赤と白の塗装はインターナショナルオレンジと呼ばれる色で、航空法に基づく塗色である。

      老朽化に伴い、2018 年に大規模なリニューアル工事が行われた。
      電波塔としての役割は東京スカイツリーに移譲されたが、観光名所として現在も人気がある。
    TXT
  },
  {
    title: "東京スカイツリーの概要",
    url: "https://example.local/tokyo-skytree",
    body: <<~TXT
      東京スカイツリーは、東京都墨田区押上に立地する高さ 634 メートルの自立式電波塔である。
      2012 年に開業し、現在は世界第 2 位の高さを誇る建造物である。

      展望デッキは 350 メートル、展望回廊は 450 メートルに設置されている。
      正式な業務名は東武鉄道による商業施設「東京スカイツリータウン」の中核施設として機能する。

      地上波デジタル放送の主要な送信所として、関東広域圏のテレビ局・ラジオ局が利用している。
    TXT
  },
  {
    title: "RAG (Retrieval-Augmented Generation) 入門",
    url: "https://example.local/rag-introduction",
    body: <<~TXT
      RAG は、検索 (retrieval) と生成 (generation) を組み合わせる LLM 応用パターンである。
      クエリに関連するドキュメントを検索し、検索結果を context として LLM に渡すことで
      ハルシネーション (事実誤認) を抑制し、最新情報や専有データを扱えるようにする。

      典型的なパイプラインは retrieve → extract → synthesize の 3 段に分かれる。
      retrieve は BM25 と密ベクタ類似度を組み合わせた hybrid retrieval が主流。
      synthesize では引用付きの応答を生成し、引用 ID を回答中に埋め込むのが一般的。
    TXT
  },
  {
    title: "ベクタ検索の基礎",
    url: "https://example.local/vector-search",
    body: <<~TXT
      ベクタ検索は、テキストや画像を高次元ベクトルに変換し、距離を比較する検索手法である。
      テキストの場合は埋め込みモデル (sentence-transformers 等) で 384〜1536 次元の
      密ベクトルに射影し、cosine 類似度で関連度を評価する。

      実用システムでは Faiss / OpenSearch / pgvector 等のベクタストアで近似最近傍 (ANN) を
      利用してスケールさせる。BM25 などの語彙ベース検索と組み合わせる hybrid retrieval が
      retrieval 品質の事実上のベースラインである。
    TXT
  },
  {
    title: "Server-Sent Events (SSE) の基礎",
    url: "https://example.local/sse-basics",
    body: <<~TXT
      Server-Sent Events (SSE) は HTTP/1.1 上で動作する単方向のサーバ → クライアント
      ストリーミングプロトコルである。Content-Type: text/event-stream で long-lived な
      レスポンスを返し、event: と data: の組を空行区切りで送り続ける。

      ブラウザ標準の EventSource API は自動再接続と Last-Event-ID をサポートするが、
      Authorization ヘッダを設定できないため、認証付きのストリーミングでは fetch + ReadableStream
      を使うことが多い。LLM API の streaming response (OpenAI, Anthropic) も SSE である。
    TXT
  }
].freeze

ActiveRecord::Base.transaction do
  Chunk.delete_all
  Source.delete_all
end

ingestor = CorpusIngestor.new
SEED_DOCUMENTS.each do |doc|
  source = Source.create!(title: doc[:title], url: doc[:url], body: doc[:body])
  chunks = ingestor.ingest(source)
  puts "[seeds] '#{doc[:title]}': #{chunks.size} chunks"
end

puts "[seeds] sources=#{Source.count} chunks=#{Chunk.count}"
