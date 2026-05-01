# ADR 0006: 固定長 + 改行優先 (再帰的) + overlap なし
#
# アルゴリズム (LangChain RecursiveCharacterTextSplitter 相当):
# 1. body を separators[0] で分割
# 2. 各断片が max_chars 以下ならそのまま chunk
# 3. 超えていたら separators[1] で再分割、以下繰り返し
# 4. 最深 (空文字 separator) でも超える場合は文字単位で機械的に切る
# 5. 連続する短い断片を greedy に結合して max_chars に近づける
#
# 学習対象として「境界またぎ問題が起きること」を残すため overlap なしを採用。
# overlap / hierarchical / semantic は派生 ADR で扱う。
module Chunkers
  class FixedLengthRecursive < Base
    DEFAULT_MAX_CHARS = 512
    # 日本語 + 英文混在を想定した区切り優先順序。最後は空文字で機械切断。
    DEFAULT_SEPARATORS = ["\n\n", "\n", "。", "、", " ", ""].freeze
    VERSION = "fixed-length-recursive-v1"

    def initialize(max_chars: DEFAULT_MAX_CHARS, separators: DEFAULT_SEPARATORS)
      raise ArgumentError, "max_chars must be > 0" if max_chars <= 0

      @max_chars = max_chars
      @separators = separators
    end

    def version
      VERSION
    end

    # @param source [Source]
    # @return [Array<{ ord: Integer, body: String }>]
    def split(source)
      pieces = recursive_split(source.body, @separators)
      merged = greedy_merge(pieces)
      merged.each_with_index.map { |body, ord| { ord: ord, body: body } }
    end

    private

    # body を separators 優先順序で再帰的に分割し、Array<String> を返す。
    # 各要素は max_chars 以下とは限らない (最深 separator でも超える場合は文字切断)。
    # 句点 / 読点 / スペース等の separator は **前の断片に貼り戻す** ことで本文を保つ
    # (LangChain RecursiveCharacterTextSplitter の `keep_separator=True` 相当)。
    def recursive_split(body, separators)
      return [] if body.empty?
      return [body] if body.length <= @max_chars

      sep, *rest = separators
      pieces =
        if sep == ""
          # 機械切断 (最深) — separator 概念がないので貼り戻し不要
          body.chars.each_slice(@max_chars).map(&:join)
        else
          # split with separator preserved on the preceding fragment
          parts = split_keeping_separator(body, sep)
          if rest.empty?
            # 最後の separator — これでも超える断片は機械切断
            parts.flat_map { |p| p.length <= @max_chars ? p : p.chars.each_slice(@max_chars).map(&:join) }
          else
            parts.flat_map { |p| p.length <= @max_chars ? p : recursive_split(p, rest) }
          end
        end

      pieces.reject(&:empty?)
    end

    # body を sep で分割し、各 sep を直前の fragment に貼り戻す。
    # "a。b。" → ["a。", "b。"]  (空末尾 fragment は drop)
    # "a。b"  → ["a。", "b"]
    def split_keeping_separator(body, sep)
      parts = body.split(sep, -1)
      result = []
      parts.each_with_index do |part, idx|
        # 最後の fragment 以外は separator を後ろに貼る
        with_sep = idx < parts.size - 1 ? part + sep : part
        result << with_sep unless with_sep.empty?
      end
      result
    end

    # 連続する短い断片を greedy に結合して max_chars に近づける。
    def greedy_merge(pieces)
      merged = []
      buffer = +""

      pieces.each do |piece|
        if (buffer.length + piece.length) <= @max_chars
          buffer << piece
        else
          merged << buffer unless buffer.empty?
          buffer = +piece.dup
        end
      end
      merged << buffer unless buffer.empty?
      merged
    end
  end
end
