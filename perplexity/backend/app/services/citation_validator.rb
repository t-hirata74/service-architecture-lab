# ADR 0004: chunk 単位 incremental parse + partial buffering で引用 marker を抽出.
#
# 使い方 (SseProxy が ai-worker の event:chunk を受け取るたびに呼ぶ):
#   validator = CitationValidator.new(allowed_source_ids: [1, 2, 3])
#   safe_text, citations = validator.process_chunk("東京タワーは [#src_1] 完成し")
#   # → safe_text = "東京タワーは [#src_1] 完成し", citations = [{ marker: "src_1", ... }]
#   safe_text2, citations2 = validator.process_chunk("た。 [#src_99]")
#   # → safe_text2 = "た。 [#src_99]", citations2 = [{ marker: "src_99", valid: false, ... }]
#   safe_text3, citations3 = validator.process_chunk("完全な [#src_2] でも分断 [#sr")
#   # → safe_text3 = "完全な [#src_2] でも分断 ", citations3 = [{ marker: "src_2", ... }]
#   #   tail "[#sr" は内部 buffer に保持され、次 chunk と合体して再評価される
#   safe_text4, citations4 = validator.process_chunk("c_3] 続き")
#   # → safe_text4 = "[#src_3] 続き", citations4 = [{ marker: "src_3", ... }]
#
# **設計の核**:
# - process_chunk は「emittable な text」と「確定した citations」を返す
# - 不完全な marker (e.g. "[#src_") は tail buffer に保持し、次 chunk と join して再評価
# - 各 marker の position は **assembled body 全体での文字オフセット**
# - allowed_source_ids との照合で `valid` を判定 (ai-worker の valid フラグは無視 = 信頼境界)
class CitationValidator
  # `[#src_<digit+>]` を厳密に検出するための完全 marker パターン
  MARKER_REGEX = /\[\#src_(\d+)\]/

  # tail buffer に残し得る partial marker の最大長.
  # marker は "[#src_999999]" のような形なので、現実的に 32 文字あれば足りる.
  # これより長い "[#src_" 候補は誤検出として捨てる (誤った tail buffer 肥大を防ぐ).
  MAX_PARTIAL_MARKER_LENGTH = 32

  attr_reader :allowed_set, :emitted_length

  def initialize(allowed_source_ids:)
    @allowed_set = allowed_source_ids.to_set
    @buffer = +""              # 未確定 tail (次 chunk と join される)
    @emitted_length = 0        # 既に safe_text として返した文字数 (citation.position の base)
  end

  # @param chunk_text [String] ai-worker からの event:chunk の data["text"]
  # @return [(String, Array<Hash>)] (frontend に流せる text, この chunk で確定した citations)
  def process_chunk(chunk_text)
    work = @buffer + chunk_text
    citations = []

    # 完全 marker をすべて抽出 → citation 配列に追加
    work.scan(MARKER_REGEX) do
      match_data = Regexp.last_match
      source_id = match_data[1].to_i
      marker_str = match_data[0]                    # "[#src_3]"
      marker_name = match_data[0][2..-2]            # "src_3" (ID 部分)
      relative_position = match_data.begin(0)
      citations << {
        marker: marker_name,
        source_id: source_id,
        position: @emitted_length + relative_position,
        valid: @allowed_set.include?(source_id),
        chunk_id: nil  # 後段 (SseProxy / Orchestrator) で hits から引いて埋める
      }
    end

    # 末尾に "[#" や "[#src_3" のような **完全 marker になりうる prefix** がある場合は
    # tail buffer に残して、emit text からは外す.
    safe_text, new_buffer = split_at_partial_marker(work)

    @buffer = new_buffer
    @emitted_length += safe_text.length

    [safe_text, citations]
  end

  # SSE 終了時に呼ぶ。tail buffer に残った文字列を最後に流す.
  # 残存 buffer に部分 marker らしきものがあっても **ここで強制 emit** する
  # (frontend に送り損ねがないように)。done イベントの直前で呼ばれる想定.
  def flush
    last = @buffer
    @buffer = +""
    @emitted_length += last.length
    last
  end

  private

  # `work` 文字列の末尾に「完全 marker になりうる部分 (`[`, `[#`, `[#s`, `[#src_3` 等)」
  # があれば、それを buffer に残して残りを safe_text として返す。
  def split_at_partial_marker(work)
    # 末尾候補: 最後の "[" 以降が完全 marker パターンの prefix になっているか?
    last_open = work.rindex("[")
    return [work, +""] if last_open.nil?

    tail = work[last_open..]

    # tail が完全 marker (`[#src_<n>]`) なら、それは scan で既に拾われているので emit して OK
    return [work, +""] if tail =~ MARKER_REGEX

    # 部分 marker prefix の判定: `[`, `[#`, `[#s`, `[#sr`, `[#src`, `[#src_`, `[#src_<digits>` のいずれか
    return [work[0...last_open], tail] if partial_marker_prefix?(tail) && tail.length <= MAX_PARTIAL_MARKER_LENGTH

    # それ以外 (e.g. "[foo" のような無関係な `[`) はそのまま emit
    [work, +""]
  end

  PARTIAL_PATTERNS = [
    /\A\[\z/,                      # "["
    /\A\[#\z/,                     # "[#"
    /\A\[#s\z/,                    # "[#s"
    /\A\[#sr\z/,                   # "[#sr"
    /\A\[#src\z/,                  # "[#src"
    /\A\[#src_\z/,                 # "[#src_"
    /\A\[#src_\d+\z/               # "[#src_3" (closing ] 待ち)
  ].freeze

  def partial_marker_prefix?(text)
    PARTIAL_PATTERNS.any? { |re| text.match?(re) }
  end
end
