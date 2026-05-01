# ADR 0001 + ADR 0002 + ADR 0006:
# - source → chunker.split → chunks 行を作成
# - ai-worker /corpus/embed で embedding 生成 (ai-worker は読み専、書き込みは Rails)
# - chunks.embedding を float32 little-endian BLOB に pack して UPDATE
# - chunker_version (ADR 0006) と embedding_version (ADR 0002) を独立して保持
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

    # Phase 2: 同 chunker_version の既存 chunk を一旦消して再作成 (rake corpus:rechunk と整合)
    Chunk.where(source_id: source.id, chunker_version: @chunker.version).delete_all

    chunks = pieces.map do |p|
      Chunk.create!(
        source: source,
        ord: p[:ord],
        chunker_version: @chunker.version,
        body: p[:body]
      )
    end

    embed_response = @ai_worker.corpus_embed(chunks.map(&:body))
    embedding_version = embed_response[:embedding_version]
    embeddings = embed_response[:embeddings]

    if embeddings.size != chunks.size
      raise AiWorkerClient::Error, "embedding count mismatch: chunks=#{chunks.size} embeddings=#{embeddings.size}"
    end

    chunks.each_with_index do |chunk, i|
      chunk.update!(embedding: embeddings[i], embedding_version: embedding_version)
    end

    chunks
  end
end
