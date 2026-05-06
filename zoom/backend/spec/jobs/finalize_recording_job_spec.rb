require "rails_helper"

# ADR 0003: at-least-once な FinalizeRecordingJob が冪等であることを fixate。
RSpec.describe FinalizeRecordingJob, type: :job do
  let(:meeting) do
    create(:meeting,
           status: "ended",
           started_at: 1.hour.ago,
           ended_at: 30.minutes.ago)
  end

  it "ended → recorded に遷移し recordings に 1 行作る" do
    expect {
      described_class.perform_now(meeting.id)
    }.to change { Recording.count }.by(1)
      .and change { meeting.reload.status }.from("ended").to("recorded")

    rec = Recording.find_by(meeting_id: meeting.id)
    expect(rec.duration_seconds).to be > 0
    expect(rec.mock_blob_path).to start_with("mock://recordings/")
  end

  it "成功時に SummarizeMeetingJob が enqueue される" do
    ActiveJob::Base.queue_adapter = :test
    expect {
      described_class.perform_now(meeting.id)
    }.to have_enqueued_job(SummarizeMeetingJob).with(meeting.id)
  end

  it "2 回実行しても recordings は 1 行のまま (at-least-once 冪等)" do
    described_class.perform_now(meeting.id)
    expect(meeting.reload.status).to eq("recorded")

    # 2 回目。status が recorded のため早期 return する経路
    expect {
      described_class.perform_now(meeting.id)
    }.not_to change { Recording.count }
  end

  it "recording_failed からの再試行で recorded に進める" do
    meeting.update!(status: "recording_failed")
    described_class.perform_now(meeting.id)
    expect(meeting.reload.status).to eq("recorded")
  end

  it "summarized 状態のミーティングには何もしない (status check で早期 return)" do
    meeting.update!(status: "summarized")
    expect {
      described_class.perform_now(meeting.id)
    }.not_to change { Recording.count }
    expect(meeting.reload.status).to eq("summarized")
  end
end
