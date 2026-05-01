require "rails_helper"

RSpec.describe "FactoryBot factories" do
  it "Source factory builds a valid record" do
    expect(create(:source)).to be_persisted
  end

  it "Chunk factory builds a valid record without embedding" do
    chunk = create(:chunk)
    expect(chunk).to be_persisted
    expect(chunk.read_attribute(:embedding)).to be_nil
  end

  it "Chunk :embedded trait stores a 256-d float32 BLOB" do
    chunk = create(:chunk, :embedded)
    expect(chunk.read_attribute(:embedding).bytesize).to eq(1024)
    expect(chunk.embedding_version).to eq("mock-hash-v1")
  end
end
