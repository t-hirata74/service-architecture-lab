export type EventType = {
  id: number;
  host_id: number;
  slug: string;
  title: string;
  duration_minutes: number;
  before_buffer_minutes: number;
  after_buffer_minutes: number;
  min_notice_minutes: number;
  max_advance_days: number;
  active: boolean;
};

export type AvailabilityRule = {
  id: number;
  host_id: number;
  event_type_id: number | null;
  rrule: string;
  tz_id: string;
  start_time_of_day: string;
  end_time_of_day: string;
  effective_from: string | null;
  effective_until: string | null;
};

export type Slot = {
  start_at_utc: string;
  end_at_utc: string;
  start_at_local: string;
};

export type Booking = {
  id: number;
  event_type_id: number;
  host_id: number;
  start_at: string;
  end_at: string;
  invitee_email: string;
  invitee_name: string | null;
  invitee_tz_id: string;
  status: "pending" | "confirmed" | "cancelled" | "completed";
};

export type PublicEventType = {
  id: number;
  host_id: number;
  slug: string;
  title: string;
  duration_minutes: number;
  host_name: string;
  slots_path: string;
};
