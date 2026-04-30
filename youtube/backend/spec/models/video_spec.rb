require "rails_helper"

RSpec.describe Video, type: :model do
  describe "validations" do
    it "requires title" do
      video = build(:video, title: nil)
      expect(video).not_to be_valid
      expect(video.errors[:title]).to include("can't be blank")
    end
  end

  describe "status enum" do
    it "exposes label-based predicates" do
      expect(build(:video, :published)).to be_published
      expect(build(:video, :transcoding)).to be_transcoding
      expect(Video.statuses[:published]).to eq(3)
    end
  end

  describe ".listable" do
    it "returns only published videos in newest-first order" do
      old_pub = create(:video, :published, title: "old", published_at: 2.days.ago)
      new_pub = create(:video, :published, title: "new", published_at: 1.hour.ago)
      create(:video, :ready,    title: "ready")
      create(:video, :transcoding, title: "transcoding")

      expect(Video.listable.map(&:title)).to eq([new_pub.title, old_pub.title])
    end
  end

  describe ".viewable" do
    it "returns ready and published only" do
      create(:video, :uploaded)
      create(:video, :transcoding)
      ready     = create(:video, :ready)
      published = create(:video, :published)

      expect(Video.viewable).to contain_exactly(ready, published)
    end
  end

  describe "tag association" do
    it "reads through video_tags" do
      video = create(:video, :published)
      video.tags << create(:tag, name: "rails")
      video.tags << create(:tag, name: "ruby")

      expect(video.tags.order(:name).pluck(:name)).to eq(%w[rails ruby])
    end
  end
end
