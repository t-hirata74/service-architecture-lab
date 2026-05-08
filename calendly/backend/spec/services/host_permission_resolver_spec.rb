require "rails_helper"

RSpec.describe HostPermissionResolver do
  let(:host) { create(:host) }
  let(:other_host) { create(:host) }
  let(:event_type) { create(:event_type, host: host) }

  describe "#owner?" do
    it "is true for own EventType" do
      expect(described_class.new(host, event_type).owner?).to be true
    end

    it "is false for other host's EventType" do
      expect(described_class.new(other_host, event_type).owner?).to be false
    end

    it "is false when user is nil" do
      expect(described_class.new(nil, event_type).owner?).to be false
    end

    it "works for Host record itself" do
      expect(described_class.new(host, host).owner?).to be true
      expect(described_class.new(host, other_host).owner?).to be false
    end
  end

  describe "#public_visible?" do
    it "is true for active event_type even from anonymous" do
      expect(described_class.new(nil, event_type).public_visible?).to be true
    end

    it "is false for inactive event_type" do
      event_type.update!(active: false)
      expect(described_class.new(nil, event_type).public_visible?).to be false
    end
  end

  describe "#can_view?" do
    it "is true for owner of inactive event_type" do
      event_type.update!(active: false)
      expect(described_class.new(host, event_type).can_view?).to be true
    end

    it "is true for anonymous on active event_type" do
      expect(described_class.new(nil, event_type).can_view?).to be true
    end

    it "is false for anonymous on inactive event_type" do
      event_type.update!(active: false)
      expect(described_class.new(nil, event_type).can_view?).to be false
    end
  end
end
