require "rails_helper"

# ADR 0002: 動的ホスト譲渡の仕様を固定する spec。
RSpec.describe Meeting, "#transfer_host_to!", type: :model do
  let(:host) { create(:user) }
  let(:new_host) { create(:user) }
  let(:meeting) { create(:meeting, host: host, status: "live", started_at: 10.minutes.ago) }

  before do
    create(:participant, :live, meeting: meeting, user: new_host)
  end

  it "live 中なら host_id を更新し、host_transfers に履歴を 1 行追加する" do
    expect {
      meeting.transfer_host_to!(new_host, reason: "voluntary")
    }.to change { meeting.reload.host_id }.from(host.id).to(new_host.id)
      .and change { HostTransfer.count }.by(1)

    transfer = HostTransfer.last
    expect(transfer).to have_attributes(
      meeting_id: meeting.id,
      from_user_id: host.id,
      to_user_id: new_host.id,
      reason: "voluntary"
    )
  end

  it "live 以外の状態では InvalidTransition" do
    meeting.update!(status: "scheduled")
    expect { meeting.transfer_host_to!(new_host) }
      .to raise_error(Meeting::InvalidTransition)
  end

  it "新ホストが live participant でないと InvalidTransition (譲渡レース時の安全装置)" do
    Participant.where(meeting: meeting, user: new_host).delete_all
    expect { meeting.transfer_host_to!(new_host) }
      .to raise_error(Meeting::InvalidTransition, /not a live participant/)
  end

  it "退出済 (left) の participant への譲渡は不可 (live のみ許可)" do
    Participant.where(meeting: meeting, user: new_host).update_all(status: "left", left_at: Time.current)
    expect { meeting.transfer_host_to!(new_host) }
      .to raise_error(Meeting::InvalidTransition)
  end

  it "現ホストへの譲渡は ArgumentError" do
    create(:participant, :live, meeting: meeting, user: host)
    expect { meeting.transfer_host_to!(host) }
      .to raise_error(ArgumentError, /must differ/)
  end
end
