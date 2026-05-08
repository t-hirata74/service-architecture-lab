module Availability
  # ADR 0003: RRULE 文字列 + 壁時計 (start_time_of_day / end_time_of_day) + tz_id を
  # `[from, to)` 範囲内の UTC datetime 区間 (`[[start_at_utc, end_at_utc], ...]`) に展開する。
  #
  # MVP: FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR の subset のみ対応。
  # ice_cube への移行は派生 ADR 候補。
  class RruleExpansion
    DAY_NAMES = { "MO" => 1, "TU" => 2, "WE" => 3, "TH" => 4, "FR" => 5, "SA" => 6, "SU" => 0 }.freeze

    def initialize(rule)
      @rule = rule
      @parsed = rule.rrule.split(";").map { |kv| kv.split("=", 2) }.to_h
      @tz = ActiveSupport::TimeZone.find_tzinfo(rule.tz_id)
    end

    # @return [Array<[Time, Time]>] UTC datetime pairs in window [from, to)
    def expand(from, to)
      raise ArgumentError, "from must be < to" unless from < to
      raise ArgumentError, "FREQ not supported" unless @parsed["FREQ"] == "WEEKLY"

      window_from = bound_by_effective(from, :max, @rule.effective_from&.beginning_of_day&.utc)
      window_to   = bound_by_effective(to, :min, @rule.effective_until&.end_of_day&.utc)
      return [] if window_from >= window_to

      target_wdays = parse_byday(@parsed["BYDAY"])

      # 走査: window 内の各日付 (host TZ ローカル) で BYDAY に一致するものを取り出し、
      # 壁時計 start/end を tz 経由で UTC に写像する。
      dates_in_local_tz(window_from, window_to).filter_map do |local_date|
        next unless target_wdays.include?(local_date.wday)
        s = local_to_utc(local_date, @rule.start_time_of_day)
        e = local_to_utc(local_date, @rule.end_time_of_day)
        next if e <= window_from || s >= window_to  # window 外は捨てる
        [ [ s, window_from ].max, [ e, window_to ].min ]
      end
    end

    private

    # ADR 0003 規律 3: 壁時計連続性。tzinfo の local_to_utc にデフォルト挙動を委ねる。
    def local_to_utc(local_date, time_of_day)
      naive = Time.new(local_date.year, local_date.month, local_date.day,
                       time_of_day.hour, time_of_day.min, time_of_day.sec)
      @tz.local_to_utc(naive)
    end

    def parse_byday(byday)
      return DAY_NAMES.values if byday.blank?
      byday.split(",").map { |d| DAY_NAMES.fetch(d) { raise ArgumentError, "unknown BYDAY: #{d}" } }
    end

    # window 範囲をローカル TZ の date 列挙 (前後 1 日マージンを含めて pull)
    def dates_in_local_tz(from_utc, to_utc)
      from_local = @tz.utc_to_local(from_utc).to_date
      to_local   = @tz.utc_to_local(to_utc).to_date
      (from_local..to_local).to_a
    end

    def bound_by_effective(default, op, effective)
      return default if effective.nil?
      [ default, effective ].public_send(op)
    end
  end
end
