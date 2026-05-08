require "rails_helper"

RSpec.describe AvailabilityRule do
  describe "validations" do
    it "requires end_time_of_day after start_time_of_day" do
      rule = build(:availability_rule, start_time_of_day: "10:00:00", end_time_of_day: "10:00:00")
      expect(rule).not_to be_valid
      expect(rule.errors[:end_time_of_day]).to be_present
    end

    it "rejects offset string as tz_id (ADR 0003)" do
      expect(build(:availability_rule, tz_id: "+09:00")).not_to be_valid
    end

    it "rejects unsupported FREQ (MVP supports WEEKLY only)" do
      expect(build(:availability_rule, rrule: "FREQ=DAILY")).not_to be_valid
      expect(build(:availability_rule, rrule: "FREQ=MONTHLY;BYMONTHDAY=1")).not_to be_valid
    end

    it "accepts FREQ=WEEKLY rule" do
      expect(build(:availability_rule, rrule: "FREQ=WEEKLY;BYDAY=MO,WE")).to be_valid
    end
  end
end
