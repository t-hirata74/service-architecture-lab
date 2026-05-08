require "rails_helper"

# review fix I-C-3: STATUSES 定数と DB CHECK 制約 (bookings_status_enum) の整合性を spec で守る。
# 片方を変えてもう片方を忘れると spec が落ちる single source of truth ガード。
RSpec.describe "Booking status — STATUSES と CHECK 制約の整合" do
  it "DB の bookings_status_enum CHECK 制約が STATUSES と完全一致する" do
    row = Booking.connection.exec_query(<<~SQL.squish).first
      SELECT CHECK_CLAUSE FROM information_schema.CHECK_CONSTRAINTS
      WHERE CONSTRAINT_NAME = 'bookings_status_enum'
    SQL
    expect(row).not_to be_nil, "bookings_status_enum CHECK 制約が見つからない"
    clause = row["CHECK_CLAUSE"]
    # MySQL は CHECK_CLAUSE で `_utf8mb4\'pending\'` のように quote をエスケープして返すため、
    # IN (...) の括弧内から英小文字 / `_` の連続を抽出して、それを「列挙された status 値」とみなす。
    in_args = clause[/in \((.+)\)/, 1].to_s
    # `_utf8mb4\'pending\'` のような token から `pending` 部分だけ抜き出す。
    db_values = in_args.scan(/\\'([a-z_]+)\\'/).flatten.uniq.sort
    expect(db_values).to eq(Booking::STATUSES.sort),
      "STATUSES (#{Booking::STATUSES}) と CHECK 制約の値 (#{db_values}) が乖離している。" \
      "新 status を追加するときは migration で CHECK 制約も更新すること。"
  end

  it "DB に直接 INSERT して不正な status を CHECK 制約で弾けることを確認" do
    expect {
      Booking.connection.execute(<<~SQL)
        INSERT INTO bookings
          (event_type_id, host_id, start_at, end_at, invitee_email, invitee_tz_id, status, created_at, updated_at)
        VALUES
          (1, 1, '2026-06-01 09:00:00', '2026-06-01 10:00:00', 'x@example.com', 'UTC', 'BOGUS', NOW(), NOW())
      SQL
    }.to raise_error(ActiveRecord::StatementInvalid)
  end
end
