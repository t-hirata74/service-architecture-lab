require "rails_helper"

# ADR 0002: 役割 (host / co_host / live_participant / guest) と操作の権限の判定行列を fixate。
RSpec.describe MeetingPermissionResolver do
  let(:host)        { create(:user, display_name: "Host") }
  let(:co_host)     { create(:user, display_name: "CoHost") }
  let(:participant) { create(:user, display_name: "Live") }
  let(:waiter)      { create(:user, display_name: "Waiter") }
  let(:stranger)    { create(:user, display_name: "Stranger") }
  let(:meeting)     { create(:meeting, host: host, status: "live", started_at: 5.minutes.ago) }

  before do
    create(:meeting_co_host, meeting: meeting, user: co_host, granted_by_user: host)
    create(:participant, :live, meeting: meeting, user: participant)
    create(:participant, meeting: meeting, user: waiter, status: "waiting")
  end

  def resolver_for(user)
    described_class.new(meeting, user)
  end

  describe "役割の判定" do
    it "host は host? のみ true" do
      r = resolver_for(host)
      expect(r.host?).to be true
      expect(r.co_host?).to be false
      expect(r.live_participant?).to be false
    end

    it "co_host は co_host? のみ true" do
      r = resolver_for(co_host)
      expect(r.host?).to be false
      expect(r.co_host?).to be true
    end

    it "live participant は live_participant? のみ true" do
      r = resolver_for(participant)
      expect(r.host?).to be false
      expect(r.co_host?).to be false
      expect(r.live_participant?).to be true
    end

    it "stranger は全て false" do
      r = resolver_for(stranger)
      expect(r.host?).to be false
      expect(r.co_host?).to be false
      expect(r.live_participant?).to be false
    end

    it "nil ユーザは全て false" do
      r = resolver_for(nil)
      expect(r.host?).to be false
      expect(r.co_host?).to be false
    end
  end

  describe "操作権限の判定行列" do
    # 行 = ユーザ役割 / 列 = 操作。true = 許可、false = 拒否。
    matrix = {
      host: {
        can_end?:                       true,
        can_open_waiting_room?:         true,
        can_admit_from_waiting_room?:   true,
        can_force_mute?:                true,
        can_transfer_host?:             true,
        can_grant_co_host?:             true,
        can_retry_recording?:           true,
        can_retry_summary?:             true,
        can_view_summary?:              true,
      },
      co_host: {
        can_end?:                       false,
        can_open_waiting_room?:         false,
        can_admit_from_waiting_room?:   true,
        can_force_mute?:                true,
        can_transfer_host?:             false,
        can_grant_co_host?:             false,
        can_retry_recording?:           false,
        can_retry_summary?:             false,
        can_view_summary?:              true,
      },
      participant: {
        can_end?:                       false,
        can_admit_from_waiting_room?:   false,
        can_force_mute?:                false,
        can_transfer_host?:             false,
        can_view_summary?:              true,
      },
      stranger: {
        can_end?:                       false,
        can_admit_from_waiting_room?:   false,
        can_force_mute?:                false,
        can_view_summary?:              false,
      },
    }

    matrix.each do |role, expectations|
      context "#{role} ユーザ" do
        let(:user_under_test) { send(role == :stranger ? :stranger : (role == :participant ? :participant : role)) }

        expectations.each do |method, expected|
          it "#{method} == #{expected}" do
            expect(resolver_for(user_under_test).public_send(method)).to eq(expected)
          end
        end
      end
    end
  end

  describe "動的譲渡で権限が即座に動くこと (ADR 0002 の主役)" do
    it "transfer_host_to! 直後に新ホストが host? になり、旧ホストは host? でなくなる" do
      # 譲渡前
      expect(resolver_for(host).host?).to be true
      expect(resolver_for(participant).host?).to be false

      meeting.transfer_host_to!(participant)
      meeting.reload

      # 譲渡後 (キャッシュ無し、即時反映)
      expect(resolver_for(host).host?).to be false
      expect(resolver_for(participant).host?).to be true
      expect(resolver_for(participant).can_end?).to be true
      expect(resolver_for(host).can_end?).to be false
    end
  end
end
