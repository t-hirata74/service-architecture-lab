require "rails_helper"

RSpec.describe Video, "state machine", type: :model do
  let(:video) { create(:video, :uploaded) }

  describe "#start_transcoding!" do
    it "transitions uploaded -> transcoding and enqueues TranscodeJob atomically" do
      expect {
        video.start_transcoding!
      }.to have_enqueued_job(TranscodeJob).with(video.id)

      expect(video.reload).to be_transcoding
    end

    it "rolls back enqueue when transition guard fails" do
      video.update!(status: :ready)

      expect {
        expect { video.start_transcoding! }.to raise_error(Video::InvalidTransition)
      }.not_to have_enqueued_job(TranscodeJob)

      expect(video.reload).to be_ready
    end
  end

  describe "#mark_ready!" do
    it "requires transcoding state" do
      expect { video.mark_ready! }.to raise_error(Video::InvalidTransition)
    end

    it "transitions transcoding -> ready" do
      video.update!(status: :transcoding)
      video.mark_ready!
      expect(video.reload).to be_ready
    end
  end

  describe "#publish!" do
    it "stamps published_at and transitions ready -> published" do
      video.update!(status: :ready, published_at: nil)
      freeze_time = Time.zone.local(2026, 5, 1, 9)
      travel_to(freeze_time) { video.publish! }

      expect(video.reload).to be_published
      expect(video.published_at.to_i).to eq(freeze_time.to_i)
    end

    it "raises InvalidTransition for non-ready states" do
      video.update!(status: :transcoding)
      expect { video.publish! }.to raise_error(Video::InvalidTransition)
      expect(video.reload).to be_transcoding
    end
  end

  describe "#retry_transcoding!" do
    it "moves failed -> transcoding and enqueues" do
      video.update!(status: :failed)

      expect { video.retry_transcoding! }.to have_enqueued_job(TranscodeJob).with(video.id)
      expect(video.reload).to be_transcoding
    end
  end

  describe "#mark_failed!" do
    it "is allowed from uploaded or transcoding only" do
      video.update!(status: :ready)
      expect { video.mark_failed! }.to raise_error(Video::InvalidTransition)
    end
  end
end
