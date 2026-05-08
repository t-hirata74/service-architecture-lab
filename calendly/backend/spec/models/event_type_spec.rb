require "rails_helper"

RSpec.describe EventType do
  describe "validations" do
    it "requires slug to be kebab-case lowercase" do
      expect(build(:event_type, slug: "Foo Bar")).not_to be_valid
      expect(build(:event_type, slug: "foo_bar")).not_to be_valid
      expect(build(:event_type, slug: "foo-bar")).to be_valid
    end

    it "scopes slug uniqueness to host" do
      host_a = create(:host)
      host_b = create(:host)
      create(:event_type, host: host_a, slug: "interview")
      expect(build(:event_type, host: host_a, slug: "interview")).not_to be_valid
      expect(build(:event_type, host: host_b, slug: "interview")).to be_valid
    end

    it "rejects non-positive duration" do
      expect(build(:event_type, duration_minutes: 0)).not_to be_valid
      expect(build(:event_type, duration_minutes: -1)).not_to be_valid
    end

    it ".active filters by active flag" do
      a = create(:event_type, active: true)
      _i = create(:event_type, active: false)
      expect(EventType.active).to contain_exactly(a)
    end
  end
end
