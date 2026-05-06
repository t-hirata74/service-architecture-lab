require "rails_helper"

# ADR 0001: 会議ライフサイクル状態機械の不変条件を固定する spec。
RSpec.describe Meeting, type: :model do
  describe "状態遷移" do
    let(:meeting) { create(:meeting) }

    it "scheduled → waiting_room → live → ended → recorded → summarized のハッピーパス" do
      expect(meeting.status).to eq("scheduled")

      meeting.open_waiting_room!
      expect(meeting.reload.status).to eq("waiting_room")

      meeting.go_live!
      expect(meeting.reload).to have_attributes(status: "live", started_at: be_present)

      meeting.end_meeting!
      expect(meeting.reload).to have_attributes(status: "ended", ended_at: be_present)

      meeting.mark_recorded!
      expect(meeting.reload.status).to eq("recorded")

      meeting.mark_summarized!
      expect(meeting.reload.status).to eq("summarized")
    end

    it "不正な遷移は InvalidTransition を投げる (scheduled から直接 live は NG)" do
      expect { meeting.go_live! }.to raise_error(Meeting::InvalidTransition)
    end

    it "scheduled から直接 ended は NG" do
      expect { meeting.end_meeting! }.to raise_error(Meeting::InvalidTransition)
    end

    it "既に target 状態のときは no-op で例外を出さない (at-least-once 冪等)" do
      meeting.update!(status: "ended", ended_at: Time.current)
      expect { meeting.end_meeting! }.not_to raise_error
      expect(meeting.reload.status).to eq("ended")
    end

    it "recording_failed → recorded への戻り遷移を許容 (再試行)" do
      meeting.update!(status: "recording_failed", started_at: 1.hour.ago, ended_at: 30.minutes.ago)
      meeting.mark_recorded!
      expect(meeting.reload.status).to eq("recorded")
    end

    it "summarize_failed → summarized への戻り遷移を許容 (再試行)" do
      meeting.update!(status: "summarize_failed", started_at: 1.hour.ago, ended_at: 30.minutes.ago)
      meeting.mark_summarized!
      expect(meeting.reload.status).to eq("summarized")
    end

    it "go_live! は started_at を初回のみ設定する (再呼び出しで上書きしない)" do
      meeting.open_waiting_room!
      meeting.go_live!
      first_started = meeting.reload.started_at
      meeting.go_live! # 既に live なので no-op
      expect(meeting.reload.started_at).to eq(first_started)
    end
  end

  describe "並行 end_meeting! (with_lock 直列化)", :concurrency do
    # use_transactional_fixtures = true だと thread 間で transaction が共有されないため、
    # この spec は実際には true でも通る（with_lock が直列化を保証）。
    # ただし真に並行性を試すなら use_transactional_fixtures = false + DatabaseCleaner だが、
    # 本リポでは shopify が webhook で同パターンを採用済み。本 spec はロック獲得時の no-op を確認。
    it "片方が end → もう片方は no-op" do
      meeting = create(:meeting, status: "live", started_at: 10.minutes.ago)
      results = []
      threads = 2.times.map do
        Thread.new do
          ActiveRecord::Base.connection_pool.with_connection do
            results << begin
              meeting.reload.end_meeting!
              :ok
            rescue Meeting::InvalidTransition => e
              e.message
            end
          end
        end
      end
      threads.each(&:join)

      expect(results).to all(eq(:ok))
      expect(meeting.reload.status).to eq("ended")
      expect(meeting.reload.ended_at).to be_present
    end
  end
end
