# ADR 0001: Rails が orchestrator として retrieve → extract → synthesize を直列に呼ぶ.
#
# Phase 3 (現状): synthesize の SSE を **同期で全消費**して answer + citations を
#   1 トランザクションで永続化する。POST /queries は完了 answer 込みで 201 を返す.
# Phase 4: SSE proxy 経路に差し替え、event:chunk を逐次 frontend に流しつつ
#   引用整合性検証 (ADR 0004) を Rails 側で行う.
#   ※ Phase 4 移行時、本クラスの assemble_from_events / synthesize 同期消費は **捨てて**
#     Controller から直接 chunked stream を読む形に書き直す予定 (ADR 0005 参照).
class RagOrchestrator
  TOP_K = 10
  ALPHA = 0.5

  class OrchestratorError < StandardError; end
  class RetrieveError    < OrchestratorError; end  # §A 開始前の失敗
  class ExtractError     < OrchestratorError; end  # §A 開始前の失敗
  class SynthesizeError  < OrchestratorError; end  # §B 開始後の失敗 (Phase 4 で event:error)
  class NoHitsError      < OrchestratorError; end

  def initialize(ai_worker: AiWorkerClient.new)
    @ai_worker = ai_worker
  end

  # @param query [Query] 永続化済み (status: pending)
  # @return [Answer]
  def run(query)
    # Phase 3 注: mark!(:streaming) は synthesize 開始直前 (HTTP 接続を張る寸前) に呼ぶ.
    # retrieve / extract が失敗した場合は pending → failed と直接遷移させる.
    # (Phase 4 SSE proxy では event:chunk を 1 件でも流したら streaming に上げる)
    hits = retrieve_or_fail(query)

    if hits.empty?
      query.mark!(:failed)
      raise NoHitsError, "retrieve returned 0 hits"
    end

    persist_query_retrievals(query, hits)

    passages = extract_or_fail(query, hits.map { |h| h[:chunk_id] })
    allowed_source_ids = hits.map { |h| h[:source_id] }.uniq

    query.mark!(:streaming)
    events = synthesize_or_fail(
      query,
      query_text: query.text,
      passages: passages,
      allowed_source_ids: allowed_source_ids
    )

    body, citation_specs = assemble_from_events(events, allowed_source_ids: allowed_source_ids)

    # answer + citations を 1 トランザクションで永続化 (ADR 0003 §C)
    answer = nil
    Answer.transaction do
      answer = Answer.create!(query: query, body: body, status: :completed)
      citation_specs.each do |spec|
        # ADR 0004: allowed_source_ids にない marker は永続化しない (検証通過分のみ).
        next unless spec[:valid]

        # 重複防止: 同じ marker が複数 chunk event に出ても 1 回だけ永続化
        # (DB 側 UNIQUE (answer_id, marker) と整合)
        Citation.find_or_create_by!(answer: answer, marker: spec[:marker]) do |c|
          c.source_id = spec[:source_id]
          c.chunk_id  = spec[:chunk_id]
          c.position  = spec[:position]
        end
      end
      query.mark!(:completed)
    end

    answer
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

  def synthesize_or_fail(query, query_text:, passages:, allowed_source_ids:)
    @ai_worker.synthesize_stream(
      query_text: query_text,
      passages: passages,
      allowed_source_ids: allowed_source_ids
    )
  rescue AiWorkerClient::Error => e
    query.mark!(:failed)
    raise SynthesizeError, "synthesize failed: #{e.message}"
  end

  # query_retrievals は audit 用 (ADR 0001).
  # extract/synthesize 後に失敗しても残す (「LLM に何が渡されたか」の証跡として価値).
  # → bulk insert で 1 SQL に圧縮.
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

  # SSE event 配列から (body, citation_specs) を組み立てる.
  # ADR 0004: ai-worker が valid: false でも本文には残し、永続化対象だけ filter する.
  # ADR 0003: chunk 順は ord で安定させる (Phase 4 SSE proxy 化で順序保証が緩むケース対策).
  def assemble_from_events(events, allowed_source_ids:)
    allowed_set = allowed_source_ids.to_set

    # chunk events を ord で sort してから body 構築
    chunk_events = events.select { |e| e[:event] == "chunk" }
                         .sort_by { |e| (e[:data]["ord"] || 0) }
    body = chunk_events.map { |e| e[:data]["text"].to_s }.join

    citation_specs = events.select { |e| e[:event] == "citation" }.map do |ev|
      source_id = ev[:data]["source_id"]
      {
        marker:    ev[:data]["marker"],
        source_id: source_id,
        chunk_id:  ev[:data]["chunk_id"],
        position:  ev[:data]["position"],
        # ADR 0004: ai-worker が返す valid フラグは無視し、Rails 側で再計算する (信頼境界)
        valid:     allowed_set.include?(source_id)
      }
    end

    [body, citation_specs]
  end
end
