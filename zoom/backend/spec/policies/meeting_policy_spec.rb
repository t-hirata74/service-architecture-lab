require "rails_helper"

# Pundit policy が Resolver を正しく呼んでいるかの薄い fixate。
# 詳細な判定行列は MeetingPermissionResolver spec が担当。
RSpec.describe MeetingPolicy do
  let(:host)        { create(:user) }
  let(:co_host)     { create(:user) }
  let(:participant) { create(:user) }
  let(:meeting)     { create(:meeting, host: host, status: "live", started_at: 5.minutes.ago) }

  before do
    create(:meeting_co_host, meeting: meeting, user: co_host, granted_by_user: host)
    create(:participant, :live, meeting: meeting, user: participant)
  end

  it "host は end_meeting? = true" do
    expect(described_class.new(host, meeting).end_meeting?).to be true
  end

  it "co_host は end_meeting? = false (ADR 0002: end は host のみ)" do
    expect(described_class.new(co_host, meeting).end_meeting?).to be false
  end

  it "co_host は admit? = true (ADR 0002: 入室許可は co_host にも委譲)" do
    expect(described_class.new(co_host, meeting).admit?).to be true
  end

  it "show? は認証済みなら誰でも許可 (招待リンク前提)、未認証は false" do
    expect(described_class.new(host, meeting).show?).to be true
    expect(described_class.new(co_host, meeting).show?).to be true
    expect(described_class.new(participant, meeting).show?).to be true
    expect(described_class.new(create(:user), meeting).show?).to be true
    expect(described_class.new(nil, meeting).show?).to be false
  end
end
