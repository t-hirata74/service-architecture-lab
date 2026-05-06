require "rails_helper"

RSpec.describe Participant, type: :model do
  it "同じ meeting に同じ user が 2 行入らない" do
    p = create(:participant)
    dup = build(:participant, meeting: p.meeting, user: p.user)
    expect(dup).not_to be_valid
  end

  describe "#admit!" do
    it "waiting → live に遷移、joined_at をセット" do
      p = create(:participant, status: "waiting")
      p.admit!
      expect(p.reload).to have_attributes(status: "live", joined_at: be_present)
    end

    it "waiting 以外からは raise" do
      p = create(:participant, :live)
      expect { p.admit! }.to raise_error(/cannot admit/)
    end
  end

  describe "#leave!" do
    it "live → left に遷移、left_at をセット" do
      p = create(:participant, :live)
      p.leave!
      expect(p.reload).to have_attributes(status: "left", left_at: be_present)
    end

    it "live 以外からは raise" do
      p = create(:participant, status: "waiting")
      expect { p.leave! }.to raise_error(/cannot leave/)
    end
  end
end
