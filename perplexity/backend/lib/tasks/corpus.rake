# ADR 0002 / 0006: コーパス取り込みと再計算用 rake task.
#
#   bundle exec rake corpus:ingest       # seeds.rb と同じ 5 ドキュメントを取り込む
#   bundle exec rake corpus:reembed      # 既存 chunk の embedding だけ再生成
#   bundle exec rake corpus:rechunk      # chunker version を変えた時に chunk から再生成
#                                         (内部で reembed も走る)
#
# 前提: ai-worker が :8030 で起動していること.
namespace :corpus do
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

  desc "Seed corpus (5 ドキュメント) を取り込む。既存 source は全削除して再投入する."
  task ingest: :environment do
    require_ai_worker!

    ActiveRecord::Base.transaction do
      Chunk.delete_all
      Source.delete_all
    end

    ingestor = CorpusIngestor.new
    SEED_DOCUMENTS.each do |doc|
      source = Source.create!(title: doc[:title], url: doc[:url], body: doc[:body])
      chunks = ingestor.ingest(source)
      puts "[corpus:ingest] '#{doc[:title]}': #{chunks.size} chunks"
    end
    puts "[corpus:ingest] sources=#{Source.count} chunks=#{Chunk.count}"
  end

  desc "既存 chunk の embedding を再生成 (chunker_version は維持)。encoder version 切替時に使用."
  task reembed: :environment do
    require_ai_worker!

    ai = AiWorkerClient.new
    targets = Chunk.where("embedding IS NULL OR embedding_version != ?", target_embedding_version(ai))
    puts "[corpus:reembed] re-embedding #{targets.count} chunks"

    targets.find_in_batches(batch_size: 100) do |batch|
      response = ai.corpus_embed(batch.map(&:body))
      version = response[:embedding_version]
      embeddings = response[:embeddings]

      Chunk.transaction do
        batch.each_with_index do |chunk, i|
          chunk.update!(embedding: embeddings[i], embedding_version: version)
        end
      end
    end
    puts "[corpus:reembed] done"
  end

  desc "Chunker 戦略を変更した後の再投入: 全 source の chunk を CorpusIngestor で再生成."
  task rechunk: :environment do
    require_ai_worker!

    ingestor = CorpusIngestor.new
    Source.find_each do |source|
      chunks = ingestor.ingest(source)
      puts "[corpus:rechunk] '#{source.title}': #{chunks.size} chunks"
    end
    puts "[corpus:rechunk] done. chunks=#{Chunk.count}"
  end

  # ---- helpers ----

  def require_ai_worker!
    require "net/http"
    base = ENV.fetch("AI_WORKER_URL", "http://localhost:8030")
    uri = URI.parse("#{base}/health")
    response = Net::HTTP.start(uri.host, uri.port, open_timeout: 1.0, read_timeout: 1.0) do |http|
      http.get(uri.path)
    end
    return if response.is_a?(Net::HTTPSuccess)

    abort "[corpus] ai-worker が起動していません (#{base}/health)。別タブで `make perplexity-ai` を起動してください"
  rescue StandardError => e
    abort "[corpus] ai-worker に到達できません (#{e.message})"
  end

  # 現行 encoder の version を取りたいが、ai-worker からは直接 expose していないので
  # /corpus/embed に dummy 1 件投げて返ってくる embedding_version を採用する.
  def target_embedding_version(ai_worker)
    ai_worker.corpus_embed(["__version_probe__"])[:embedding_version]
  end
end
