require "rails_helper"

RSpec.describe Answer, type: :model do
  it "is valid with body and query" do
    expect(build(:answer)).to be_valid
  end

  it "rejects empty body" do
    expect(build(:answer, body: "")).not_to be_valid
  end

  it "rejects invalid status" do
    expect(build(:answer, status: "bogus")).not_to be_valid
  end

  it "destroys citations on cascade" do
    a = create(:answer)
    source = create(:source)
    create(:citation, answer: a, source: source)
    expect { a.destroy! }.to change { Citation.count }.by(-1)
  end

  it "orders citations by position ascending" do
    a = create(:answer)
    source = create(:source)
    c2 = create(:citation, answer: a, source: source, position: 50, marker: "src_2")
    c1 = create(:citation, answer: a, source: source, position: 10, marker: "src_1")
    expect(a.citations.to_a).to eq([c1, c2])
  end
end
