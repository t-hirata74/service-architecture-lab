require "rails_helper"

RSpec.describe Comment, type: :model do
  let(:video) { create(:video, :published) }

  describe "validations" do
    it "requires body" do
      expect(build(:comment, video: video, body: "")).not_to be_valid
    end

    it "rejects body longer than 2000 characters" do
      expect(build(:comment, video: video, body: "x" * 2_001)).not_to be_valid
    end
  end

  describe "thread depth" do
    it "allows replies to top-level comments" do
      top   = create(:comment, video: video)
      reply = build(:comment, video: video, parent: top)
      expect(reply).to be_valid
    end

    it "rejects replies-of-replies (1段までに制限)" do
      top   = create(:comment, video: video)
      reply = create(:comment, video: video, parent: top)
      reply_of_reply = build(:comment, video: video, parent: reply)
      expect(reply_of_reply).not_to be_valid
      expect(reply_of_reply.errors[:parent_id]).to be_present
    end
  end

  describe ".top_level" do
    it "returns only comments without parent_id, oldest-first" do
      first = create(:comment, video: video)
      create(:comment, video: video, parent: first)
      second = create(:comment, video: video)

      expect(Comment.where(video: video).top_level).to eq([first, second])
    end
  end
end
