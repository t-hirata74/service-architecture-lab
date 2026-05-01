require 'rails_helper'

RSpec.describe IssueNumberAllocator do
  let(:repository) { create(:repository) }

  it "starts from 1" do
    expect(described_class.next_for(repository)).to eq(1)
  end

  it "increments monotonically" do
    expect(described_class.next_for(repository)).to eq(1)
    expect(described_class.next_for(repository)).to eq(2)
    expect(described_class.next_for(repository)).to eq(3)
  end

  it "scopes per repository" do
    other = create(:repository)
    expect(described_class.next_for(repository)).to eq(1)
    expect(described_class.next_for(other)).to eq(1)
    expect(described_class.next_for(repository)).to eq(2)
  end

  it "uses with_lock to serialize concurrent updates (ADR 0003)" do
    repository # eager create
    expect_any_instance_of(RepositoryIssueNumber).to receive(:with_lock).and_call_original
    described_class.next_for(repository)
  end
end
