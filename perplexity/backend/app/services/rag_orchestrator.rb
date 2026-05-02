# ADR 0001 / 0003 / 0004: Rails が retrieve → extract → synthesize を直列に呼ぶ orchestrator.
#
# Phase 4 (現状):
#   - prepare(query): retrieve + extract + query_retrievals 永続化 + (passages, hits, allowed_source_ids) を返す
#   - stream_to(query, response_stream): prepare + SseProxy で synthesize を frontend に proxy + 永続化
#
# Phase 3 までの run() は同期 RAG 用で、Phase 4 の SSE proxy 経路に統合された.
class RagOrchestrator
  TOP_K = 10
  ALPHA = 0.5

  class OrchestratorError < StandardError; end
  class RetrieveError    < OrchestratorError; end  # §A 開始前の失敗
  class ExtractError     < OrchestratorError; end  # §A 開始前の失敗
  class SynthesizeError  < OrchestratorError; end  # §B 開始後の失敗 (event:error)
  class NoHitsError      < OrchestratorError; end

  Prepared = Struct.new(:hits, :passages, :allowed_source_ids, :hits_by_source_id, keyword_init: true)

  def initialize(ai_worker: AiWorkerClient.new, sse_proxy: SseProxy.new)
    @ai_worker = ai_worker
    @sse_proxy = sse_proxy
  end

  # SSE 開始前に走る (ADR 0003 §A 領域).
  # 失敗時は HTTP 5xx で frontend に返せる (まだ stream を開いていない).
  # @param query [Query] 永続化済み (status: pending)
  # @return [Prepared]
  def prepare(query)
    hits = retrieve_or_fail(query)

    if hits.empty?
      query.mark!(:failed)
      raise NoHitsError, "retrieve returned 0 hits"
    end

    persist_query_retrievals(query, hits)

    passages = extract_or_fail(query, hits.map { |h| h[:chunk_id] })
    allowed_source_ids = hits.map { |h| h[:source_id] }.uniq
    hits_by_source_id = hits.each_with_object({}) { |h, acc| acc[h[:source_id]] ||= h }

    Prepared.new(
      hits: hits,
      passages: passages,
      allowed_source_ids: allowed_source_ids,
      hits_by_source_id: hits_by_source_id
    )
  end

  # SSE 開始後に走る (ADR 0003 §B 領域).
  # 失敗時は event:error を流して answer.status=failed で永続化.
  # @param query [Query] prepare 後 (status: streaming)
  # @param prepared [Prepared]
  # @param response_stream [#write] Rails::Live の response.stream (or テスト用 IO)
  # @return [Answer] 永続化済み answer
  def stream_to(query, prepared, response_stream)
    query.mark!(:streaming)

    result = @sse_proxy.stream(
      query_text: query.text,
      passages: prepared.passages,
      allowed_source_ids: prepared.allowed_source_ids,
      response_stream: response_stream,
      hits_by_source_id: prepared.hits_by_source_id
    )

    # 永続化 (ADR 0003 §C: answer + citations を 1 トランザクションで).
    answer = nil
    Answer.transaction do
      answer = Answer.create!(query: query, body: result[:body], status: :completed)
      result[:citations].each do |c|
        # ADR 0004: valid 通過分だけ永続化 (SseProxy 内で既に valid filter 済み).
        Citation.find_or_create_by!(answer: answer, marker: c[:marker]) do |cit|
          cit.source_id = c[:source_id]
          cit.chunk_id  = c[:chunk_id]
          cit.position  = c[:position]
        end
      end
      query.mark!(:completed)
    end

    answer
  rescue SseProxy::Error => e
    query.mark!(:failed)
    raise SynthesizeError, "synthesize failed: #{e.message}"
  end

  private

  def retrieve_or_fail(query)
    @ai_worker.retrieve(query_text: query.text, top_k: TOP_K, alpha: ALPHA)
  rescue AiWorkerClient::Error => e
    query.mark!(:failed)
    raise RetrieveError, "retrieve failed: #{e.message}"
  end

  def extract_or_fail(query, chunk_ids)
    @ai_worker.extract(chunk_ids: chunk_ids)
  rescue AiWorkerClient::Error => e
    query.mark!(:failed)
    raise ExtractError, "extract failed: #{e.message}"
  end

  # query_retrievals は audit 用 (ADR 0001).
  # extract/synthesize 後に失敗しても残す (証跡として価値).
  def persist_query_retrievals(query, hits)
    now = Time.current
    rows = hits.each_with_index.map do |hit, rank|
      {
        query_id:     query.id,
        chunk_id:     hit[:chunk_id],
        source_id:    hit[:source_id],
        bm25_score:   hit[:bm25_score],
        cosine_score: hit[:cosine_score],
        fused_score:  hit[:fused_score],
        rank:         rank,
        created_at:   now
      }
    end
    QueryRetrieval.insert_all!(rows)
  end
end
