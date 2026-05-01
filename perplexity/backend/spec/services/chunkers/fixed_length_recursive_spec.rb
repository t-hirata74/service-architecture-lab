require "rails_helper"

RSpec.describe Chunkers::FixedLengthRecursive do
  let(:source) { Source.new(title: "t", body: body) }
  subject(:chunker) { described_class.new(max_chars: max_chars) }

  let(:max_chars) { 50 }

  describe "#version" do
    it "returns a stable identifier" do
      expect(chunker.version).to eq("fixed-length-recursive-v1")
    end
  end

  describe "#split" do
    context "with body shorter than max_chars" do
      let(:body) { "短い文章。" }

      it "returns a single chunk" do
        result = chunker.split(source)
        expect(result.size).to eq(1)
        expect(result.first).to eq(ord: 0, body: "短い文章。")
      end
    end

    context "with paragraph separators" do
      let(:body) { "段落1の本文。" + ("\n\n") + "段落2の本文。" }

      it "splits on the highest-priority separator (\\n\\n)" do
        result = chunker.split(source)
        # 短いので greedy merge で 1 chunk になる
        expect(result.size).to eq(1)
        expect(result.first[:body]).to include("段落1")
        expect(result.first[:body]).to include("段落2")
      end
    end

    context "with body exceeding max_chars" do
      # 100 文字 → max=50 で 2-3 chunk に分割される想定
      let(:body) do
        ("あ" * 40 + "。") + ("い" * 40 + "。")
      end

      it "splits and respects max_chars boundary" do
        result = chunker.split(source)
        expect(result.size).to be >= 2
        result.each { |c| expect(c[:body].length).to be <= max_chars }
      end

      it "assigns sequential ord starting from 0" do
        result = chunker.split(source)
        expect(result.map { |c| c[:ord] }).to eq((0...result.size).to_a)
      end
    end

    context "with very long single token" do
      let(:body) { "x" * 130 } # separator が無い → 機械切断

      it "falls back to fixed-size character splitting" do
        result = chunker.split(source)
        # 50 + 50 + 30 = 3 chunk
        expect(result.size).to eq(3)
        expect(result[0][:body].length).to eq(50)
        expect(result[1][:body].length).to eq(50)
        expect(result[2][:body].length).to eq(30)
      end
    end

    context "with empty body" do
      let(:body) { "" }

      it "returns an empty array" do
        expect(chunker.split(source)).to eq([])
      end
    end

    context "with greedy merging of many small pieces" do
      # 各「文。」は 2 文字 + 句点 = 3 文字。max=50 / 3 ≒ 16 個まで結合される想定
      let(:body) { (["短文。"] * 30).join }

      it "merges sequential small pieces up to max_chars" do
        result = chunker.split(source)
        expect(result.size).to be >= 2
        # 最初の chunk は max_chars 直前まで詰めてある (50 文字以下)
        expect(result.first[:body].length).to be <= max_chars
        # 全文の長さは保たれる (overlap なし)
        joined = result.map { |c| c[:body] }.join
        expect(joined).to eq(body)
      end
    end
  end

  describe "argument validation" do
    it "rejects max_chars <= 0" do
      expect { described_class.new(max_chars: 0) }.to raise_error(ArgumentError)
      expect { described_class.new(max_chars: -1) }.to raise_error(ArgumentError)
    end
  end
end
