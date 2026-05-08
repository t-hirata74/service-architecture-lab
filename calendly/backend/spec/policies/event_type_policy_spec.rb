require "rails_helper"

RSpec.describe EventTypePolicy do
  let(:host) { create(:host) }
  let(:other_host) { create(:host) }
  let(:event_type) { create(:event_type, host: host) }

  describe "#show?" do
    it "permits owner" do
      expect(described_class.new(host, event_type).show?).to be true
    end

    it "permits anonymous on active event_type" do
      expect(described_class.new(nil, event_type).show?).to be true
    end

    it "denies anonymous on inactive event_type" do
      event_type.update!(active: false)
      expect(described_class.new(nil, event_type).show?).to be false
    end
  end

  describe "#update? / #destroy?" do
    it "permits owner" do
      expect(described_class.new(host, event_type).update?).to be true
      expect(described_class.new(host, event_type).destroy?).to be true
    end

    it "denies non-owner" do
      expect(described_class.new(other_host, event_type).update?).to be false
      expect(described_class.new(other_host, event_type).destroy?).to be false
    end

    it "denies anonymous" do
      expect(described_class.new(nil, event_type).update?).to be false
    end
  end

  describe "Scope" do
    it "returns only owner's records" do
      e1 = create(:event_type, host: host)
      _e2 = create(:event_type, host: other_host)
      resolved = EventTypePolicy::Scope.new(host, EventType).resolve
      expect(resolved).to contain_exactly(e1, event_type)
    end

    it "returns none for nil user" do
      create(:event_type, host: host)
      expect(EventTypePolicy::Scope.new(nil, EventType).resolve).to be_empty
    end
  end
end
