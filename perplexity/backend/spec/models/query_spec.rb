require "rails_helper"

RSpec.describe Query, type: :model do
  it "is valid with text and user" do
    expect(build(:query)).to be_valid
  end

  it "rejects invalid status" do
    q = build(:query, status: "bogus")
    expect(q).not_to be_valid
  end

  it "rejects empty text" do
    expect(build(:query, text: "")).not_to be_valid
  end

  describe "predicate methods" do
    %w[pending streaming completed failed].each do |s|
      it "#{s}? returns true when status == #{s}" do
        q = build(:query, status: s)
        expect(q.public_send("#{s}?")).to be true
      end
    end
  end

  describe "#mark!" do
    it "transitions status" do
      q = create(:query)
      q.mark!(:streaming)
      expect(q.reload).to be_streaming
    end

    it "raises for invalid status" do
      q = create(:query)
      expect { q.mark!(:bogus) }.to raise_error(ArgumentError)
    end
  end

  it "destroys answer and retrievals on cascade" do
    q = create(:query)
    create(:answer, query: q)
    create(:query_retrieval, query: q)
    expect { q.destroy! }.to change { Answer.count }.by(-1).and change { QueryRetrieval.count }.by(-1)
  end
end
