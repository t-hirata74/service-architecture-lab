require "rails_helper"

RSpec.describe Availability::RruleExpansion do
  let(:host) { create(:host, default_tz_id: "Asia/Tokyo") }

  describe "WEEKLY MO-FR / Asia/Tokyo" do
    let(:rule) do
      create(:availability_rule,
             host: host,
             rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
             start_time_of_day: "09:00:00",
             end_time_of_day:   "17:00:00",
             tz_id: "Asia/Tokyo")
    end

    it "expands a Mon-Fri week into 5 occurrences (UTC)" do
      # 2026-06-01 (Mon) .. 2026-06-07 (Sun) JST
      from = Time.utc(2026, 5, 31, 15, 0)  # Mon 00:00 JST
      to   = Time.utc(2026, 6, 7, 15, 0)   # Sun 00:00 JST
      result = described_class.new(rule).expand(from, to)
      expect(result.size).to eq(5)
      # 月曜 (2026-06-01 JST) の 09:00 = 00:00 UTC
      expect(result.first[0]).to eq(Time.utc(2026, 6, 1, 0, 0))
      expect(result.first[1]).to eq(Time.utc(2026, 6, 1, 8, 0))  # 17:00 JST = 08:00 UTC
    end

    it "skips Sat/Sun" do
      from = Time.utc(2026, 6, 5, 15, 0)  # Sat 00:00 JST
      to   = Time.utc(2026, 6, 7, 15, 0)  # Mon 00:00 JST (next week)
      result = described_class.new(rule).expand(from, to)
      expect(result.size).to eq(0)  # Sat と Sun のみ → 0 件
    end
  end

  describe "DST 跨ぎ — America/New_York 春の切替 (ADR 0003 規律 3)" do
    let(:rule) do
      create(:availability_rule,
             host: host,
             rrule: "FREQ=WEEKLY;BYDAY=WE",
             start_time_of_day: "14:00:00",
             end_time_of_day:   "15:00:00",
             tz_id: "America/New_York")
    end

    it "壁時計 14:00 が DST 跨ぎ前後で維持される (UTC offset は変わる)" do
      # 2026 年 米国 DST 開始は 3 月 8 日 (Sun)。
      # 3/4 (Wed) は EST = UTC-5 → 14:00 EST = 19:00 UTC
      # 3/11 (Wed) は EDT = UTC-4 → 14:00 EDT = 18:00 UTC
      from = Time.utc(2026, 3, 1, 0, 0)
      to   = Time.utc(2026, 3, 15, 0, 0)
      result = described_class.new(rule).expand(from, to)
      expect(result.size).to eq(2)

      mar4 = result[0]
      mar11 = result[1]
      expect(mar4[0]).to eq(Time.utc(2026, 3, 4, 19, 0))   # 14:00 EST
      expect(mar11[0]).to eq(Time.utc(2026, 3, 11, 18, 0)) # 14:00 EDT
      # 壁時計は両方 14:00。UTC は -5 ⇄ -4 で 1 時間ずれている。
    end
  end

  describe "DST 跨ぎ — America/New_York 秋の切替 fallback (review fix I-E-1)" do
    let(:rule) do
      create(:availability_rule,
             host: host,
             rrule: "FREQ=WEEKLY;BYDAY=WE",
             start_time_of_day: "14:00:00",
             end_time_of_day:   "15:00:00",
             tz_id: "America/New_York")
    end

    it "壁時計 14:00 が 秋 DST 跨ぎ前後でも維持される (UTC offset は EDT→EST に動く)" do
      # 2026 年 米国 DST 終了は 11/1 (Sun) 02:00 EDT → 01:00 EST。
      # 10/28 (Wed) は EDT = UTC-4 → 14:00 EDT = 18:00 UTC
      # 11/4 (Wed) は EST = UTC-5 → 14:00 EST = 19:00 UTC
      from = Time.utc(2026, 10, 25, 0, 0)
      to   = Time.utc(2026, 11, 8, 0, 0)
      result = described_class.new(rule).expand(from, to)
      expect(result.size).to eq(2)

      oct28 = result[0]
      nov4  = result[1]
      expect(oct28[0]).to eq(Time.utc(2026, 10, 28, 18, 0)) # 14:00 EDT
      expect(nov4[0]).to eq(Time.utc(2026, 11, 4, 19, 0))   # 14:00 EST
      # 壁時計は両方 14:00。秋切替で UTC offset は -4 → -5 に増えるが、壁時計は連続。
    end
  end

  describe "rejects unsupported FREQ" do
    let(:rule) do
      AvailabilityRule.new(host: host, rrule: "FREQ=DAILY",
                           start_time_of_day: "09:00:00", end_time_of_day: "17:00:00",
                           tz_id: "Asia/Tokyo")
    end

    it "raises ArgumentError on expand" do
      expect { described_class.new(rule).expand(Time.utc(2026, 1, 1), Time.utc(2026, 1, 8)) }
        .to raise_error(ArgumentError, /FREQ not supported/)
    end
  end

  describe "effective_from / effective_until で範囲を絞る" do
    let(:rule) do
      create(:availability_rule,
             host: host,
             rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
             start_time_of_day: "09:00:00", end_time_of_day: "17:00:00",
             tz_id: "Asia/Tokyo",
             effective_from: Date.new(2026, 6, 3),
             effective_until: Date.new(2026, 6, 4))
    end

    it "is bounded by effective_from / effective_until" do
      from = Time.utc(2026, 5, 31, 15, 0)
      to   = Time.utc(2026, 6, 7, 15, 0)
      result = described_class.new(rule).expand(from, to)
      # 6/3 (Wed), 6/4 (Thu) のみ
      expect(result.size).to eq(2)
    end
  end
end
