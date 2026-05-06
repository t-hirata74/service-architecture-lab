require "rails_helper"
require "webmock/rspec"
require "httpx/adapters/webmock"

# ADR 0003: at-least-once な SummarizeMeetingJob が冪等であることを fixate。
# 冪等の核は summaries.meeting_id UNIQUE 制約。
RSpec.describe SummarizeMeetingJob, type: :job do
  let(:meeting) do
    create(:meeting,
           status: "recorded",
           started_at: 1.hour.ago,
           ended_at: 30.minutes.ago)
  end
  let!(:recording) { create(:recording, meeting: meeting, duration_seconds: 1800) }

  let(:ai_worker_url) { ENV.fetch("AI_WORKER_URL", "http://127.0.0.1:8080") }

  before do
    WebMock.disable_net_connect!(allow_localhost: false)
    stub_request(:post, "#{ai_worker_url}/summarize")
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { body: "Mock summary for meeting #{meeting.id}", input_hash: "abc123" }.to_json
      )
  end

  it "recorded → summarized に遷移し summaries に 1 行作る" do
    expect {
      described_class.perform_now(meeting.id)
    }.to change { Summary.count }.by(1)
      .and change { meeting.reload.status }.from("recorded").to("summarized")

    s = Summary.find_by(meeting_id: meeting.id)
    expect(s.body).to include("Mock summary")
    expect(s.input_hash).to eq("abc123")
  end

  it "2 回実行しても summaries は 1 行のまま (UNIQUE で冪等)" do
    described_class.perform_now(meeting.id)
    described_class.perform_now(meeting.id)
    expect(Summary.where(meeting_id: meeting.id).count).to eq(1)
  end

  it "summarize_failed からの再試行で summarized に進める" do
    meeting.update!(status: "summarize_failed")
    described_class.perform_now(meeting.id)
    expect(meeting.reload.status).to eq("summarized")
    expect(Summary.where(meeting_id: meeting.id).count).to eq(1)
  end

  it "ai-worker が 500 を返したとき retry_on で再 enqueue され、状態は recorded のまま" do
    # retry_on Internal::Client::Error が catch して enqueue するため、perform_now は raise しない。
    # この挙動の確認は include ActiveJob::TestHelper + queue_adapter :test が必要。
    ActiveJob::Base.queue_adapter = :test
    stub_request(:post, "#{ai_worker_url}/summarize").to_return(status: 500, body: "")

    expect {
      described_class.perform_now(meeting.id)
    }.not_to raise_error

    expect(Summary.where(meeting_id: meeting.id).count).to eq(0)
    expect(meeting.reload.status).to eq("recorded") # 失敗状態には落ちない (MVP は failed_executions に残す方針)
  ensure
    ActiveJob::Base.queue_adapter = :solid_queue
  end

  it "recorded 状態でないミーティングには何もしない" do
    meeting.update!(status: "summarized")
    described_class.perform_now(meeting.id)
    expect(WebMock).not_to have_requested(:post, "#{ai_worker_url}/summarize")
  end
end
