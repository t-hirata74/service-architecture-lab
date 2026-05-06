require "rails_helper"

# ADR 0002: host_transfers は append-only。永続化後の UPDATE / DELETE は禁止。
RSpec.describe HostTransfer, "append-only", type: :model do
  let(:transfer) { create(:host_transfer) }

  it "永続化後は readonly?" do
    expect(transfer.readonly?).to be true
  end

  it "update! はエラーになる" do
    expect { transfer.update!(reason: "forced") }
      .to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "destroy はエラーになる" do
    expect { transfer.destroy }
      .to raise_error(ActiveRecord::ReadOnlyRecord)
  end

  it "DB スキーマに updated_at カラムが無い (append-only シグナル)" do
    expect(HostTransfer.column_names).not_to include("updated_at")
    expect(HostTransfer.column_names).to include("created_at")
  end

  it "from_user_id と to_user_id が同一だと validation エラー" do
    user = create(:user)
    transfer = build(:host_transfer, from_user: user, to_user: user)
    expect(transfer).not_to be_valid
    expect(transfer.errors[:to_user_id]).to be_present
  end

  it "reason は voluntary / host_left / forced のいずれか" do
    %w[voluntary host_left forced].each do |r|
      expect(build(:host_transfer, reason: r)).to be_valid
    end
    expect(build(:host_transfer, reason: "bogus")).not_to be_valid
  end

  it "アプリコードに UPDATE / DELETE しているメソッドが無いことを fixate" do
    # 静的検査: app/ 配下に host_transfers の update/delete 呼び出しがないこと。
    grep_target = Rails.root.join("app").to_s
    cmd = "grep -rE 'host_transfers?\\.(update|delete|destroy)' #{grep_target} 2>/dev/null || true"
    matches = `#{cmd}`.lines.reject(&:empty?)
    expect(matches).to be_empty, "found host_transfers UPDATE/DELETE in app/: #{matches.join}"
  end
end
