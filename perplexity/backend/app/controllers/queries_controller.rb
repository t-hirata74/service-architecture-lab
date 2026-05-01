# Phase 3: 同期 RAG (POST /queries が retrieve → extract → synthesize を全部走らせて
# 完了 answer を 201 で返す)。Phase 4 で SSE proxy 経路 (GET /queries/:id/stream) を追加.
class QueriesController < ApplicationController
  before_action :authenticate_user!

  # POST /queries
  # body: { text: "..." }
  def create
    text = params.require(:text)
    query = current_user.queries.create!(text: text)

    begin
      answer = RagOrchestrator.new.run(query)
    rescue RagOrchestrator::NoHitsError
      return render json: { error: "no_hits", query_id: query.id }, status: :unprocessable_entity
    rescue RagOrchestrator::OrchestratorError => e
      return render json: { error: "ai_worker_unavailable", detail: e.message, query_id: query.id }, status: :service_unavailable
    end

    render json: serialize_query(query.reload, answer), status: :created
  end

  # GET /queries/:id
  def show
    query = current_user.queries.find_by(id: params[:id])
    return render json: { error: "not_found" }, status: :not_found if query.nil?

    render json: serialize_query(query, query.answer)
  end

  private

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
