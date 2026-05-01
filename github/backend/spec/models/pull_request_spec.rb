require 'rails_helper'

RSpec.describe PullRequest, type: :model do
  let(:pr) { create(:pull_request) }

  describe "#close!" do
    it "moves open -> closed" do
      pr.close!
      expect(pr.state).to eq("closed")
      expect(pr.mergeable_state).to eq("closed_state")
    end

    it "is idempotent guard: cannot close twice" do
      pr.close!
      expect { pr.close! }.to raise_error(PullRequest::InvalidTransition)
    end
  end

  describe "#merge!" do
    it "moves open + mergeable -> merged" do
      pr.merge!
      expect(pr.state).to eq("merged")
      expect(pr.mergeable_state).to eq("merged_state")
    end

    it "rejects merge when conflict" do
      pr.update!(mergeable_state: :conflict)
      expect { pr.merge! }.to raise_error(PullRequest::InvalidTransition)
      expect(pr.reload.state).to eq("open")
    end

    it "rejects merge when already closed" do
      pr.close!
      expect { pr.merge! }.to raise_error(PullRequest::InvalidTransition)
    end
  end
end
