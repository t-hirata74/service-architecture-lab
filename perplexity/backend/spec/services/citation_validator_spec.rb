require "rails_helper"

RSpec.describe CitationValidator do
  describe "#process_chunk" do
    context "with no markers in input" do
      it "returns input as-is and no citations" do
        v = described_class.new(allowed_source_ids: [1, 2])
        text, citations = v.process_chunk("東京タワーは 1958 年に")
        expect(text).to eq("東京タワーは 1958 年に")
        expect(citations).to be_empty
      end
    end

    context "with a single complete marker in input" do
      it "extracts the marker as a citation and returns the text intact" do
        v = described_class.new(allowed_source_ids: [3])
        text, citations = v.process_chunk("本文 [#src_3] の続き")
        expect(text).to eq("本文 [#src_3] の続き")
        expect(citations).to contain_exactly(
          a_hash_including(marker: "src_3", source_id: 3, valid: true)
        )
      end
    end

    context "with multiple markers" do
      it "extracts each as a separate citation" do
        v = described_class.new(allowed_source_ids: [1, 2])
        text, citations = v.process_chunk("a [#src_1] b [#src_2] c")
        expect(text).to eq("a [#src_1] b [#src_2] c")
        expect(citations.map { |c| c[:source_id] }).to eq([1, 2])
      end
    end

    context "with a marker source_id not in allowed_source_ids" do
      it "marks valid: false (ADR 0004 信頼境界 / Rails 側で再判定)" do
        v = described_class.new(allowed_source_ids: [1])
        _, citations = v.process_chunk("外 [#src_99]")
        expect(citations.first).to include(marker: "src_99", source_id: 99, valid: false)
      end
    end

    context "with chunk boundary splitting a marker" do
      it "buffers the partial tail and re-evaluates with the next chunk" do
        v = described_class.new(allowed_source_ids: [3])

        text1, citations1 = v.process_chunk("完全な [#src_2] と分断 [#sr")
        # "[#sr" は partial marker → buffer に保持
        expect(text1).to eq("完全な [#src_2] と分断 ")
        expect(citations1.size).to eq(1)
        expect(citations1.first[:source_id]).to eq(2)
        expect(citations1.first[:valid]).to be false  # 2 は allowed 外

        text2, citations2 = v.process_chunk("c_3] 続き")
        # 1 つ目の chunk の "[#sr" + 2 つ目の "c_3]" が join されて完全 marker に
        expect(text2).to eq("[#src_3] 続き")
        expect(citations2.first).to include(marker: "src_3", source_id: 3, valid: true)
      end
    end

    context "with a non-marker `[` in input" do
      it "does not buffer brackets unrelated to marker syntax" do
        v = described_class.new(allowed_source_ids: [])
        text, _ = v.process_chunk("配列は [1, 2, 3] です")
        # "[" 以降が完全 marker の prefix にならないのでそのまま emit
        expect(text).to eq("配列は [1, 2, 3] です")
      end
    end

    context "with a `[` in the middle followed by full marker" do
      it "extracts the inner marker even when other [ exist" do
        v = described_class.new(allowed_source_ids: [5])
        text, citations = v.process_chunk("[Note] please cite [#src_5]")
        expect(text).to eq("[Note] please cite [#src_5]")
        expect(citations.first[:source_id]).to eq(5)
      end
    end

    context "position tracking across chunks" do
      it "reports positions as character offsets in the assembled body" do
        v = described_class.new(allowed_source_ids: [1, 2])
        v.process_chunk("先頭テキスト")  # 6 chars emitted
        _, citations = v.process_chunk("追加 [#src_1] 末尾")
        # body 全体 = "先頭テキスト追加 [#src_1] 末尾"
        # "[#src_1]" の開始位置 = 6 (先頭テキスト) + 3 (追加 + space) = 9
        expect(citations.first[:position]).to eq(9)
      end
    end

    context "extremely long partial marker tail (defense against malicious input)" do
      it "stops buffering when partial marker exceeds MAX_PARTIAL_MARKER_LENGTH" do
        v = described_class.new(allowed_source_ids: [])
        long_partial = "[#src_" + ("9" * 50)  # 56 文字、MAX=32 を超える
        text, _ = v.process_chunk(long_partial)
        # 過長 partial は buffer に残さず emit (true marker 化しないと判断)
        expect(text).to eq(long_partial)
      end
    end

    context "duplicate markers" do
      it "emits a citation for each occurrence (永続化側で uniqueness 担保 / find_or_create_by!)" do
        v = described_class.new(allowed_source_ids: [1])
        _, citations = v.process_chunk("[#src_1] 中略 [#src_1]")
        expect(citations.size).to eq(2)
        expect(citations.first[:position]).to eq(0)
        # "[#src_1] 中略 [#src_1]" = 8 + " 中略 " (4) → 2 つ目は 12
        expect(citations.last[:position]).to eq(12)
      end
    end
  end

  describe "#flush" do
    it "emits any remaining tail buffer text" do
      v = described_class.new(allowed_source_ids: [1])
      v.process_chunk("partial [#sr")
      flushed = v.flush
      expect(flushed).to eq("[#sr")
    end

    it "returns empty string when buffer is empty" do
      v = described_class.new(allowed_source_ids: [])
      v.process_chunk("complete")
      expect(v.flush).to eq("")
    end
  end

  describe "#emitted_length" do
    it "tracks total emitted character count" do
      v = described_class.new(allowed_source_ids: [1])
      v.process_chunk("12345")
      v.process_chunk("[#src_1]")
      # emitted = "12345" (5) + "[#src_1]" (8) = 13
      expect(v.emitted_length).to eq(13)
    end
  end
end
