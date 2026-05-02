# Phase 4: 非同期 SSE API.
#
# - POST /queries          : Query を pending で作成、即 201 + stream_url を返す
# - GET  /queries/:id/stream : ActionController::Live で SSE proxy
#                              (retrieve + extract + synthesize-stream を中で実行)
# - GET  /queries/:id        : 完了後の answer + citations を返す (再描画用)
#
# ADR 0003: SSE 三段階 degradation:
#   §A 開始前 (prepare 中) : 5xx を素直に返す。frontend は SSE を開かない
#   §B 開始後 (synthesize 中) : event:error を流して response.stream.close
#   §C done 後             : Answer.transaction で原子的永続化
class QueriesController < ApplicationController
  include ActionController::Live

  before_action :authenticate_user!

  # POST /queries
  # body: { text: "..." }
  def create
    text = params.require(:text)
    query = current_user.queries.create!(text: text)
    render json: {
      query_id: query.id,
      status: query.status,
      stream_url: stream_query_url(query)  # named route from `resources :queries do member { get :stream } end`
    }, status: :created
  end

  # GET /queries/:id/stream
  # SSE で retrieve → extract → synthesize を逐次配信.
  def stream
    # SSE response header (ADR 0003).
    response.headers["Content-Type"]      = "text/event-stream"
    response.headers["Cache-Control"]     = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers.delete("Content-Length")

    query = current_user.queries.find_by(id: params[:id])
    if query.nil?
      response.status = 404
      write_error(response.stream, "not_found")
      return
    end

    if query.completed? || query.failed?
      # 既に完了/失敗済みのクエリで再 stream を要求された場合は
      # event:error を 1 件流して即終了 (ADR 0001 「再生成は新リクエスト扱い」).
      write_error(response.stream, "already_finalized", status: query.status)
      return
    end

    orchestrator = RagOrchestrator.new

    # ---- Phase 4 §A 領域 ----
    # SSE 開始前なので、失敗時は HTTP status code を変えて返せる.
    begin
      prepared = orchestrator.prepare(query)
    rescue RagOrchestrator::NoHitsError
      response.status = 422
      write_error(response.stream, "no_hits")
      return
    rescue RagOrchestrator::RetrieveError, RagOrchestrator::ExtractError => e
      response.status = 503
      write_error(response.stream, "ai_worker_unavailable", detail: e.message)
      return
    end

    # ---- Phase 4 §B 領域 ----
    # SSE は既に開始する。失敗は event:error で通知.
    begin
      orchestrator.stream_to(query, prepared, response.stream)
    rescue RagOrchestrator::SynthesizeError => e
      write_error(response.stream, "ai_worker_disconnect", detail: e.message)
    end
  ensure
    response.stream.close if response.stream.respond_to?(:close)
    # ADR 0005: ActionController::Live は thread connection を明示解放しないと
    # transactional fixtures 配下でテストが詰まる.
    ActiveRecord::Base.connection_pool.release_connection if defined?(ActiveRecord::Base)
  end

  # GET /queries/:id
  def show
    query = current_user.queries.includes(answer: :citations).find_by(id: params[:id])
    return render json: { error: "not_found" }, status: :not_found if query.nil?

    render json: serialize_query(query, query.answer)
  end

  private

  def write_error(stream, reason, **extra)
    payload = { reason: reason, **extra }
    stream.write("event: error\ndata: #{payload.to_json}\n\n")
  end

  def serialize_query(query, answer)
    {
      query: {
        id: query.id,
        text: query.text,
        status: query.status,
        created_at: query.created_at
      },
      answer: answer.nil? ? nil : {
        id: answer.id,
        body: answer.body,
        status: answer.status,
        citations: answer.citations.map do |c|
          { id: c.id, marker: c.marker, position: c.position, source_id: c.source_id, chunk_id: c.chunk_id }
        end
      }
    }
  end
end
