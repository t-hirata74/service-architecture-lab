export type MeetingStatus =
  | "scheduled"
  | "waiting_room"
  | "live"
  | "ended"
  | "recorded"
  | "summarized"
  | "recording_failed"
  | "summarize_failed";

export interface Meeting {
  id: number;
  title: string;
  status: MeetingStatus;
  host_id: number;
  scheduled_start_at: string;
  started_at: string | null;
  ended_at: string | null;
  participants?: Participant[];
  co_hosts?: number[];
}

export interface Participant {
  id: number;
  user_id: number;
  display_name: string;
  status: "waiting" | "live" | "left";
}

export interface Summary {
  meeting_id: number;
  body: string;
  generated_at: string;
}
