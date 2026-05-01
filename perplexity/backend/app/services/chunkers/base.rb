# ADR 0006: チャンク分割戦略の差し替え可能性のためのインターフェース
#
# 全 chunker は #split(source) で Array<{ ord:, body: }> を返し、
# #version で 64 文字以内のバージョン文字列を返す。
# 戦略を変えたら version をインクリメントする規律。
module Chunkers
  class Base
    # @param source [Source]
    # @return [Array<Hash{Symbol => Object}>] [{ ord: 0, body: "..." }, ...]
    def split(_source)
      raise NotImplementedError
    end

    # @return [String] e.g. "fixed-length-recursive-v1"
    def version
      raise NotImplementedError
    end
  end
end
