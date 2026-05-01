require "rails_helper"

RSpec.describe Chunk, type: :model do
  let(:source) { Source.create!(title: "T", body: "B") }

  describe "#embedding=" do
    it "packs a 256-d float array into little-endian float32 BLOB (1024 bytes)" do
      vec = Array.new(256) { |i| i * 0.01 }
      chunk = Chunk.new(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: vec)
      blob = chunk.read_attribute(:embedding)
      expect(blob.bytesize).to eq(1024)
    end

    # ADR 0002: ai-worker (numpy.frombuffer dtype="<f4") との byte 一致を保証する
    # ため、native byte order に依存しない実 byte pattern で little-endian を縛る.
    # IEEE 754 single-precision の 1.0 = 0x3F800000 = bytes [0x00, 0x00, 0x80, 0x3F] (LE)
    it "encodes 1.0 as IEEE 754 little-endian float32 bytes (0x00 0x00 0x80 0x3F)" do
      vec = [1.0] + Array.new(255, 0.0)
      chunk = Chunk.new(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: vec)
      blob = chunk.read_attribute(:embedding)
      first_four = blob.bytes.first(4)
      expect(first_four).to eq([0x00, 0x00, 0x80, 0x3F])
    end

    it "encodes -2.0 as little-endian float32 (0x00 0x00 0x00 0xC0)" do
      vec = [-2.0] + Array.new(255, 0.0)
      chunk = Chunk.new(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: vec)
      blob = chunk.read_attribute(:embedding)
      expect(blob.bytes.first(4)).to eq([0x00, 0x00, 0x00, 0xC0])
    end

    it "round-trips through embedding_vector with float32 precision" do
      vec = Array.new(256) { |i| (i % 7) * 0.1 }
      chunk = Chunk.create!(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: vec)
      restored = chunk.reload.embedding_vector
      expect(restored.size).to eq(256)
      vec.each_with_index do |v, i|
        expect(restored[i]).to be_within(1e-6).of(v)
      end
    end

    it "rejects non 256-d arrays" do
      expect {
        Chunk.new(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: [1.0, 2.0])
      }.to raise_error(ArgumentError, /256-d/)
    end

    it "rejects arrays with NaN or Infinity (毒データ防止)" do
      bad = [Float::NAN] + Array.new(255, 0.0)
      expect {
        Chunk.new(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: bad)
      }.to raise_error(ArgumentError, /finite/)

      bad2 = [Float::INFINITY] + Array.new(255, 0.0)
      expect {
        Chunk.new(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: bad2)
      }.to raise_error(ArgumentError, /finite/)
    end

    it "accepts nil for an unembedded chunk" do
      chunk = Chunk.create!(source: source, ord: 0, chunker_version: "v1", body: "x", embedding: nil)
      expect(chunk.embedding_vector).to be_nil
    end
  end
end
