# ADR 0001: Rails が orchestrator として retrieve → extract → synthesize を直列に呼ぶ.
#
# Phase 3 (現状): synthesize の SSE を **同期で全消費**して answer + citations を
#   1 トランザクションで永続化する。POST /queries は完了 answer 込みで 201 を返す.
# Phase 4: SSE proxy 経路に差し替え、event:chunk を逐次 frontend に流しつつ
#   引用整合性検証 (ADR 0004) を Rails 側で行う.
class RagOrchestrator
  TOP_K = 10
  ALPHA = 0.5

  def initialize(ai_worker: AiWorkerClient.new)
    @ai_worker = ai_worker
  end

  # @param query [Query] 永続化済み (status: pending)
  # @return [Answer]
  def run(query)
    query.mark!(:streaming)

    # 1. retrieve
    hits = @ai_worker.retrieve(query_text: query.text, top_k: TOP_K, alpha: ALPHA)

    Query.transaction do
      hits.each_with_index do |hit, rank|
        QueryRetrieval.create!(
          query: query,
          chunk_id: hit[:chunk_id],
          source_id: hit[:source_id],
          bm25_score: hit[:bm25_score],
          cosine_score: hit[:cosine_score],
          fused_score: hit[:fused_score],
          rank: rank
        )
      end
    end

    if hits.empty?
      query.mark!(:failed)
      raise NoHitsError, "retrieve returned 0 hits"
    end

    # 2. extract
    chunk_ids = hits.map { |h| h[:chunk_id] }
    passages = @ai_worker.extract(chunk_ids: chunk_ids)

    # 3. synthesize (Phase 3: SSE 同期消費)
    allowed_source_ids = hits.map { |h| h[:source_id] }.uniq
    events = @ai_worker.synthesize_stream(
      query_text: query.text,
      passages: passages,
      allowed_source_ids: allowed_source_ids
    )

    body, citation_specs = assemble_from_events(events, allowed_source_ids: allowed_source_ids)

    # 4. answer + citations を 1 トランザクションで永続化 (ADR 0003 §C)
    answer = nil
    Answer.transaction do
      answer = Answer.create!(query: query, body: body, status: :completed)
      citation_specs.each do |spec|
        # ADR 0004: allowed_source_ids にない marker は永続化しない (検証通過分のみ).
        next unless spec[:valid]

        Citation.create!(
          answer: answer,
          source_id: spec[:source_id],
          chunk_id: spec[:chunk_id],
          marker: spec[:marker],
          position: spec[:position]
        )
      end
      query.mark!(:completed)
    end

    answer
  rescue AiWorkerClient::Error => e
    query.mark!(:failed) if query.persisted?
    raise OrchestratorError, "ai-worker call failed: #{e.message}"
  end

  class OrchestratorError < StandardError; end
  class NoHitsError < OrchestratorError; end

  private

  # SSE event 配列から (body, citation_specs) を組み立てる.
  # ADR 0004: ai-worker が valid: false でも本文には残し、永続化対象だけ filter する.
  def assemble_from_events(events, allowed_source_ids:)
    allowed_set = allowed_source_ids.to_set
    body = +""
    citation_specs = []

    events.each do |ev|
      case ev[:event]
      when "chunk"
        body << ev[:data]["text"].to_s
      when "citation"
        source_id = ev[:data]["source_id"]
        is_valid = allowed_set.include?(source_id)
        citation_specs << {
          marker: ev[:data]["marker"],
          source_id: source_id,
          chunk_id: ev[:data]["chunk_id"],
          position: ev[:data]["position"],
          valid: is_valid
        }
      when "done"
        # 完了マーカー — 何もしない
      end
    end

    [body, citation_specs]
  end
end
