require "rails_helper"

RSpec.describe Availability::SlotsService do
  let(:host) { create(:host, default_tz_id: "Asia/Tokyo") }
  let(:event_type) do
    create(:event_type, host: host, duration_minutes: 60,
           before_buffer_minutes: 0, after_buffer_minutes: 0,
           min_notice_minutes: 0, max_advance_days: 365)
  end
  let!(:rule) do
    create(:availability_rule, host: host, rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
           start_time_of_day: "09:00:00", end_time_of_day: "17:00:00", tz_id: "Asia/Tokyo")
  end

  # 月曜 (2026-06-01 JST) の 1 日窓 = JST 09:00-17:00 = UTC 00:00-08:00 → 8 slots
  let(:mon_window_from) { Time.utc(2026, 5, 31, 15, 0) }  # Mon 00:00 JST
  let(:mon_window_to)   { Time.utc(2026, 6, 1, 15, 0) }   # Tue 00:00 JST
  let(:fixed_now) { Time.utc(2026, 5, 1, 0, 0) }

  describe "happy path" do
    it "returns 8 slots in JST 09:00-17:00 / Mon 2026-06-01" do
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      expect(slots.size).to eq(8)
      expect(slots.first.start_at).to eq(Time.utc(2026, 6, 1, 0, 0))
      expect(slots.last.end_at).to eq(Time.utc(2026, 6, 1, 8, 0))
    end
  end

  describe "busy_period が間にある場合" do
    it "subtracts the busy interval and returns remaining slots" do
      create(:busy_period, host: host,
             start_at: Time.utc(2026, 6, 1, 3, 0),  # 12:00 JST
             end_at:   Time.utc(2026, 6, 1, 4, 0))  # 13:00 JST
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      starts = slots.map(&:start_at)
      # 12:00-13:00 JST = 03:00-04:00 UTC スロットだけが消える
      expect(starts).not_to include(Time.utc(2026, 6, 1, 3, 0))
      expect(slots.size).to eq(7)
    end
  end

  describe "active booking は除外、cancelled は無視" do
    it "excludes confirmed booking" do
      create(:booking, host: host, event_type: event_type,
             start_at: Time.utc(2026, 6, 1, 3, 0),
             end_at:   Time.utc(2026, 6, 1, 4, 0),
             status: "confirmed")
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      expect(slots.size).to eq(7)
    end

    it "ignores cancelled booking (ADR 0002)" do
      create(:booking, host: host, event_type: event_type,
             start_at: Time.utc(2026, 6, 1, 3, 0),
             end_at:   Time.utc(2026, 6, 1, 4, 0),
             status: "cancelled")
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      expect(slots.size).to eq(8)
    end
  end

  describe "buffer minutes が頭尾を切る" do
    it "shrinks free interval by before_buffer / after_buffer" do
      event_type.update!(before_buffer_minutes: 30, after_buffer_minutes: 30)
      # 9:00-17:00 → 9:30-16:30 → 60 min duration で 7 slots
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      expect(slots.size).to eq(7)
    end
  end

  describe "min_notice_minutes が頭を切る" do
    it "drops slots earlier than now + min_notice" do
      event_type.update!(min_notice_minutes: 60 * 24)  # 1 日
      # now = 2026-06-01 00:00 UTC, min_notice 24h → 6/2 以降のみ
      tight_now = Time.utc(2026, 6, 1, 0, 0)
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: tight_now).call
      expect(slots).to be_empty
    end
  end

  describe "max_advance_days が尾を切る" do
    it "drops slots beyond now + max_advance_days" do
      event_type.update!(max_advance_days: 1)
      far_now = Time.utc(2026, 5, 25, 0, 0)  # 6/1 はちょうど 7 日先
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: far_now).call
      expect(slots).to be_empty
    end
  end

  # review fix I-C-4: host-global rule (event_type_id=NULL) と event_type 固有 rule の併存挙動を fixate。
  describe "host-global rule と event_type 固有 rule の併用" do
    it "host-global と event_type 固有が重なる時間帯は merge して重複 slot を生まない" do
      # host-global は同じ MO-FR 09:00-17:00 (factory のデフォルト)
      # event_type 固有として MO-FR 09:00-12:00 (短縮) を追加
      create(:availability_rule, host: host, event_type: event_type,
             rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
             start_time_of_day: "09:00:00", end_time_of_day: "12:00:00", tz_id: "Asia/Tokyo")
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      # global 09-17 と event 09-12 の合算 = 09-17 のまま (merge_overlapping)。slot 数は 8 で変わらない。
      expect(slots.size).to eq(8)
    end
  end

  describe "隣接予約は OK (closed-open ADR 0001)" do
    it "allows back-to-back slots without overlap" do
      create(:booking, host: host, event_type: event_type,
             start_at: Time.utc(2026, 6, 1, 0, 0),
             end_at:   Time.utc(2026, 6, 1, 1, 0),
             status: "confirmed")
      slots = described_class.new(event_type: event_type, from: mon_window_from, to: mon_window_to, now: fixed_now).call
      # 09:00-10:00 JST が予約済み → 残り 7 slots、最初は 10:00 JST = 01:00 UTC
      expect(slots.first.start_at).to eq(Time.utc(2026, 6, 1, 1, 0))
      expect(slots.size).to eq(7)
    end
  end
end
