require "rails_helper"
require "webmock/rspec"
require "httpx/adapters/webmock"

# ADR 0001 / 0003 統合: ended → recorded → summarized のパイプライン全体を 1 spec で確認。
RSpec.describe "ended → recorded → summarized pipeline", type: :integration do
  include ActiveJob::TestHelper

  let(:host) { create(:user) }
  let(:meeting) do
    create(:meeting,
           host: host,
           status: "ended",
           started_at: 1.hour.ago,
           ended_at: 30.minutes.ago)
  end
  let(:ai_worker_url) { ENV.fetch("AI_WORKER_URL", "http://127.0.0.1:8080") }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
    stub_request(:post, "#{ai_worker_url}/summarize")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { body: "summary text", input_hash: "h" }.to_json
      )
  end

  around do |example|
    original = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :test
    example.run
    ActiveJob::Base.queue_adapter = original
  end

  it "FinalizeRecordingJob → SummarizeMeetingJob チェインが ended を summarized に進める" do
    perform_enqueued_jobs do
      FinalizeRecordingJob.perform_later(meeting.id)
    end

    meeting.reload
    expect(meeting.status).to eq("summarized")
    expect(Recording.where(meeting_id: meeting.id).count).to eq(1)
    expect(Summary.where(meeting_id: meeting.id).count).to eq(1)
  end

  it "パイプライン全体を 2 回流しても recordings/summaries は 1 行ずつ" do
    perform_enqueued_jobs do
      FinalizeRecordingJob.perform_later(meeting.id)
      FinalizeRecordingJob.perform_later(meeting.id) # at-least-once 重複の模擬
    end

    expect(Recording.where(meeting_id: meeting.id).count).to eq(1)
    expect(Summary.where(meeting_id: meeting.id).count).to eq(1)
  end
end
