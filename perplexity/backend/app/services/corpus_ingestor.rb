# ADR 0001 + ADR 0002 + ADR 0006:
# - source → chunker.split → chunks 行を作成
# - ai-worker /corpus/embed で embedding 生成 (ai-worker は読み専、書き込みは Rails)
# - chunks.embedding を float32 little-endian BLOB に pack して UPDATE
# - chunker_version (ADR 0006) と embedding_version (ADR 0002) を独立して保持
#
# 原子性 (ADR 0003 §C と整合):
#   ai-worker 呼び出しは長時間 HTTP なのでトランザクション内に閉じ込めると DB lock を
#   保持する時間が伸びる。代わりに **embed 成功確認後に DB を 1 トランザクションで
#   更新** する 2 段構成を採る。embed 失敗時は旧 chunk を一切壊さない.
class CorpusIngestor
  def initialize(chunker: Chunkers::FixedLengthRecursive.new, ai_worker: AiWorkerClient.new)
    @chunker = chunker
    @ai_worker = ai_worker
  end

  # @param source [Source] 永続化済み or 未保存
  # @return [Array<Chunk>] 永続化済み chunk 群
  def ingest(source)
    source.save! if source.new_record?

    pieces = @chunker.split(source)
    return [] if pieces.empty?

    # Step 1: ai-worker で embedding を先に生成 (DB lock を持たずに HTTP 待機).
    # 失敗時は旧 chunk が無事のまま例外伝播。
    bodies = pieces.map { |p| p[:body] }
    embed_response = @ai_worker.corpus_embed(bodies)
    embedding_version = embed_response[:embedding_version]
    embeddings = embed_response[:embeddings]

    if embeddings.size != pieces.size
      raise AiWorkerClient::Error, "embedding count mismatch: chunks=#{pieces.size} embeddings=#{embeddings.size}"
    end

    # Step 2: 旧 chunk 削除 + 新 chunk 作成 + embedding 書き込みを 1 トランザクションに包む.
    # 中途半端な状態 (embedding=NULL の chunk が残る等) を防ぐ。
    new_chunks = []
    Chunk.transaction do
      Chunk.where(source_id: source.id, chunker_version: @chunker.version).delete_all
      pieces.each_with_index do |p, i|
        new_chunks << Chunk.create!(
          source: source,
          ord: p[:ord],
          chunker_version: @chunker.version,
          body: p[:body],
          embedding: embeddings[i],
          embedding_version: embedding_version
        )
      end
    end

    new_chunks
  end
end
