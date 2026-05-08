module Availability
  # ADR 0001: availability merge アルゴリズム。
  # availability_rules を展開 → busy_periods + bookings(active) を引いて空き区間 → duration スライス
  # → buffer / min_notice / max_advance で頭尾切り。
  #
  # 戻り値: `[ { start_at: Time(UTC), end_at: Time(UTC) }, ... ]` の slot 配列。
  # 呼び出し側で invitee_tz への整形 (ADR 0003) は行う。
  class SlotsService
    Slot = Struct.new(:start_at, :end_at, keyword_init: true)

    def initialize(event_type:, from:, to:, now: Time.current)
      @event_type = event_type
      @host = event_type.host
      @from = from.utc
      @to   = to.utc
      @now  = now.utc
    end

    def call
      window_from, window_to = clamp_to_policy
      return [] if window_from >= window_to

      free_intervals = compute_free_intervals(window_from, window_to)
      free_intervals.flat_map { |s, e| slice_into_slots(s, e) }
    end

    private

    # min_notice / max_advance_days で window を狭める
    def clamp_to_policy
      effective_from = [ @from, @now + @event_type.min_notice_minutes.minutes ].max
      effective_to   = [ @to, @now + @event_type.max_advance_days.days ].min
      [ effective_from, effective_to ]
    end

    # 「ルールで OK な区間」 - 「busy + active booking」 = free intervals
    def compute_free_intervals(from, to)
      rule_intervals = collect_rule_intervals(from, to)
      busy_intervals = collect_busy_intervals(from, to)
      subtract_intervals(rule_intervals, busy_intervals)
    end

    def collect_rule_intervals(from, to)
      scope = @host.availability_rules.where("event_type_id IS NULL OR event_type_id = ?", @event_type.id)
      scope.flat_map { |rule| RruleExpansion.new(rule).expand(from, to) }
        .then { |arr| merge_overlapping(arr) }
    end

    def collect_busy_intervals(from, to)
      busy = @host.busy_periods.overlapping(from, to).pluck(:start_at, :end_at)
      booked = Booking.overlapping(@host.id, from, to).pluck(:start_at, :end_at)
      merge_overlapping(busy + booked)
    end

    # [[s,e],...] を非減少 start でソート + 隣接 / 重なりを統合
    def merge_overlapping(intervals)
      return [] if intervals.empty?
      sorted = intervals.sort_by { |s, _| s }
      merged = [ sorted.first.dup ]
      sorted.drop(1).each do |s, e|
        last = merged.last
        if s <= last[1]
          last[1] = e if e > last[1]
        else
          merged << [ s, e ]
        end
      end
      merged
    end

    # rule_intervals (free) - busy_intervals (busy) = free intervals
    def subtract_intervals(rule_intervals, busy_intervals)
      result = []
      rule_intervals.each do |rs, re|
        cursor = rs
        busy_intervals.each do |bs, be|
          break if bs >= re
          next if be <= cursor
          result << [ cursor, bs ] if bs > cursor
          cursor = be
        end
        result << [ cursor, re ] if cursor < re
      end
      result.reject { |s, e| e <= s }
    end

    # buffer 適用後に duration ぶんスライス
    def slice_into_slots(s, e)
      step = @event_type.duration_minutes.minutes
      buffered_start = s + @event_type.before_buffer_minutes.minutes
      buffered_end   = e - @event_type.after_buffer_minutes.minutes
      slots = []
      cursor = buffered_start
      while cursor + step <= buffered_end
        slots << Slot.new(start_at: cursor, end_at: cursor + step)
        cursor += step
      end
      slots
    end
  end
end
