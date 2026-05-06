require "rails_helper"

# ADR 0003: recordings.meeting_id / summaries.meeting_id の UNIQUE 制約が
# at-least-once な FinalizeRecordingJob / SummarizeMeetingJob の冪等保証の核。
RSpec.describe "Recording / Summary uniqueness (ADR 0003)", type: :model do
  let(:meeting) { create(:meeting, status: "ended") }

  describe Recording do
    it "同一 meeting_id で 2 件目を作ろうとすると DB レベルで弾く" do
      create(:recording, meeting: meeting)
      dup = build(:recording, meeting: meeting)
      expect { dup.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "validation でも uniqueness を弾く" do
      create(:recording, meeting: meeting)
      dup = build(:recording, meeting: meeting)
      expect(dup).not_to be_valid
      expect(dup.errors[:meeting_id]).to be_present
    end
  end

  describe Summary do
    it "同一 meeting_id で 2 件目を作ろうとすると DB レベルで弾く" do
      create(:summary, meeting: meeting)
      dup = build(:summary, meeting: meeting)
      expect { dup.save!(validate: false) }
        .to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "upsert (insert ... on duplicate key) で冪等に書ける" do
      Summary.upsert(
        { meeting_id: meeting.id, body: "v1", input_hash: "h1", generated_at: Time.current,
          created_at: Time.current, updated_at: Time.current }
      )
      Summary.upsert(
        { meeting_id: meeting.id, body: "v2", input_hash: "h2", generated_at: Time.current,
          created_at: Time.current, updated_at: Time.current }
      )
      expect(Summary.where(meeting_id: meeting.id).count).to eq(1)
      # MySQL の ON DUPLICATE KEY UPDATE の挙動: 後勝ち。
      expect(Summary.find_by(meeting_id: meeting.id).body).to eq("v2")
    end
  end
end
