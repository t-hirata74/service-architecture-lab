class Chunk < ApplicationRecord
  belongs_to :source

  # ADR 0002: 256 次元 float32 little-endian
  EMBEDDING_DIMS = 256
  EMBEDDING_PACK = "e*" # little-endian single-precision (32-bit) float

  # 配列 → BLOB (Rails が write 時に呼ぶ)
  def embedding=(value)
    return super(nil) if value.nil?

    array = value.to_a
    raise ArgumentError, "embedding must be #{EMBEDDING_DIMS}-d (got #{array.size})" if array.size != EMBEDDING_DIMS

    # NaN / Infinity は pack("e*") で黙って通って毒データになるので明示的に reject
    unless array.all? { |v| v.is_a?(Numeric) && v.respond_to?(:finite?) && v.finite? }
      raise ArgumentError, "embedding must contain only finite Numeric values"
    end

    super(array.pack(EMBEDDING_PACK))
  end

  # BLOB → 配列 (numpy 側は ai-worker が直接 frombuffer する。
  # ここは Rails 内で扱う場合の補助メソッド)
  def embedding_vector
    blob = read_attribute(:embedding)
    return nil if blob.blank?

    blob.unpack(EMBEDDING_PACK)
  end
end
