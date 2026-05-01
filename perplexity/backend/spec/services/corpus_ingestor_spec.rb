require "rails_helper"

RSpec.describe CorpusIngestor do
  let(:chunker) { Chunkers::FixedLengthRecursive.new(max_chars: 100) }
  let(:source) { Source.new(title: "T", body: "東京タワーは 1958 年に完成した。" + ("文" * 200)) }

  def stub_embed(texts:, version: "mock-hash-v1")
    embeddings = texts.map { |_| Array.new(256, 0.0).each_with_index.map { |_, i| (i % 7) * 0.01 } }
    stub_request(:post, "http://localhost:8030/corpus/embed")
      .with(body: hash_including("texts" => texts))
      .to_return(
        status: 200,
        body: { embeddings: embeddings, embedding_version: version }.to_json,
        headers: { "Content-Type" => "application/json" }
      )
  end

  it "splits the source, calls /corpus/embed, and persists embedding BLOBs" do
    pieces = chunker.split(source)
    stub_embed(texts: pieces.map { |p| p[:body] })

    ingestor = described_class.new(chunker: chunker)
    chunks = ingestor.ingest(source)

    expect(chunks.size).to eq(pieces.size)
    chunks.each do |c|
      expect(c.chunker_version).to eq("fixed-length-recursive-v1")
      expect(c.embedding_version).to eq("mock-hash-v1")
      blob = c.read_attribute(:embedding)
      expect(blob.bytesize).to eq(1024)
      expect(c.embedding_vector.size).to eq(256)
    end
  end

  it "replaces existing chunks of the same chunker_version on re-ingest (idempotent)" do
    pieces = chunker.split(source)
    stub_embed(texts: pieces.map { |p| p[:body] })

    ingestor = described_class.new(chunker: chunker)
    first = ingestor.ingest(source)
    second = ingestor.ingest(source)

    expect(second.map(&:id)).not_to eq(first.map(&:id))  # 行が再作成される
    # でも DB 上の chunk 数は変わらない
    expect(Chunk.where(source_id: source.id, chunker_version: chunker.version).count).to eq(pieces.size)
  end

  it "raises when ai-worker returns an embedding count mismatch" do
    stub_request(:post, "http://localhost:8030/corpus/embed")
      .to_return(
        status: 200,
        body: { embeddings: [Array.new(256, 0.0)], embedding_version: "v1" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    ingestor = described_class.new(chunker: chunker)
    expect { ingestor.ingest(source) }.to raise_error(AiWorkerClient::Error, /count mismatch/)
  end

  it "wraps ai-worker connection errors as AiWorkerClient::Error" do
    stub_request(:post, "http://localhost:8030/corpus/embed").to_timeout

    ingestor = described_class.new(chunker: chunker)
    expect { ingestor.ingest(source) }.to raise_error(AiWorkerClient::Error, /unreachable/)
  end

  # 原子性: ai-worker 失敗時に既存 chunk が壊れないこと (ADR 0003 §C / レビュー指摘 §2.1)
  it "preserves prior chunks when ai-worker fails on re-ingest (atomic on failure)" do
    pieces = chunker.split(source)
    stub_embed(texts: pieces.map { |p| p[:body] })
    initial = described_class.new(chunker: chunker).ingest(source)
    initial_ids = initial.map(&:id)
    initial_count = Chunk.where(source_id: source.id).count
    expect(initial_count).to eq(pieces.size)

    # 2 回目の ingest で ai-worker が落ちる
    WebMock.reset!
    stub_request(:post, "http://localhost:8030/corpus/embed").to_timeout

    expect {
      described_class.new(chunker: chunker).ingest(source)
    }.to raise_error(AiWorkerClient::Error)

    # 旧 chunk は一切壊れていない
    surviving = Chunk.where(source_id: source.id).pluck(:id)
    expect(surviving.sort).to eq(initial_ids.sort)
    expect(Chunk.where(source_id: source.id).count).to eq(initial_count)
    Chunk.where(source_id: source.id).each do |c|
      expect(c.read_attribute(:embedding)).to be_present
      expect(c.embedding_version).to eq("mock-hash-v1")
    end
  end

  # 原子性: count mismatch 時も旧 chunk が壊れない
  it "preserves prior chunks when ai-worker returns count mismatch on re-ingest" do
    pieces = chunker.split(source)
    stub_embed(texts: pieces.map { |p| p[:body] })
    described_class.new(chunker: chunker).ingest(source)
    initial_count = Chunk.where(source_id: source.id).count

    WebMock.reset!
    stub_request(:post, "http://localhost:8030/corpus/embed")
      .to_return(
        status: 200,
        body: { embeddings: [Array.new(256, 0.0)], embedding_version: "v2" }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    expect {
      described_class.new(chunker: chunker).ingest(source)
    }.to raise_error(AiWorkerClient::Error, /count mismatch/)
    expect(Chunk.where(source_id: source.id).count).to eq(initial_count)
  end
end
