require "rails_helper"

RSpec.describe "Bookings API", type: :request do
  let!(:auth) { signup_and_login(email: "host-b@example.com") }
  let(:host) { auth[0] }
  let(:headers) { auth[1] }
  let!(:event_type) { create(:event_type, host: host, duration_minutes: 60, min_notice_minutes: 0, active: true) }

  describe "POST /bookings (public)" do
    it "creates a confirmed booking from unauthenticated invitee" do
      post "/bookings",
           params: { event_type_id: event_type.id,
                     start_at: "2026-06-01T09:00:00Z",
                     invitee_email: "guest@example.com",
                     invitee_tz_id: "Asia/Tokyo" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:created), response.body
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("confirmed")
      expect(body["host_id"]).to eq(host.id)
    end

    it "returns 409 BookingConflict on overlap (ADR 0002)" do
      create(:booking, host: host, event_type: event_type,
             start_at: Time.utc(2026, 6, 1, 9, 0), end_at: Time.utc(2026, 6, 1, 10, 0),
             status: "confirmed")
      post "/bookings",
           params: { event_type_id: event_type.id,
                     start_at: "2026-06-01T09:30:00Z",
                     invitee_email: "guest2@example.com",
                     invitee_tz_id: "UTC" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:conflict)
      expect(JSON.parse(response.body)["error"]).to eq("booking_conflict")
    end

    it "returns 404 if event_type is inactive" do
      event_type.update!(active: false)
      post "/bookings",
           params: { event_type_id: event_type.id,
                     start_at: "2026-06-01T09:00:00Z",
                     invitee_email: "guest@example.com",
                     invitee_tz_id: "UTC" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:not_found)
    end

    # review fix I-E-3: invitee からの不正入力を controller 層で 422 で弾けるか
    it "returns 422 with invalid_param for non-ISO8601 start_at (review fix C-A-1)" do
      post "/bookings",
           params: { event_type_id: event_type.id, start_at: "2026-99-99",
                     invitee_email: "guest@example.com", invitee_tz_id: "UTC" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("invalid_param")
      expect(body["param"]).to eq("start_at")
    end

    it "returns 422 with invalid_param for unknown invitee_tz_id" do
      post "/bookings",
           params: { event_type_id: event_type.id, start_at: "2026-06-01T09:00:00Z",
                     invitee_email: "guest@example.com", invitee_tz_id: "Mars/Olympus" }.to_json,
           headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["param"]).to eq("invitee_tz_id")
    end
  end

  describe "GET /bookings (host)" do
    let!(:b1) { create(:booking, host: host, event_type: event_type, start_at: Time.utc(2026, 6, 1, 9), end_at: Time.utc(2026, 6, 1, 10)) }
    let!(:other_host) { create(:host) }
    let!(:other_et) { create(:event_type, host: other_host) }
    let!(:b2) { create(:booking, host: other_host, event_type: other_et) }

    it "scopes to own bookings only" do
      get "/bookings", headers: headers
      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |b| b["id"] }
      expect(ids).to include(b1.id)
      expect(ids).not_to include(b2.id)
    end
  end

  describe "DELETE /bookings/:id (host cancel)" do
    let!(:b) { create(:booking, host: host, event_type: event_type, status: "confirmed") }

    it "cancels own booking" do
      delete "/bookings/#{b.id}", headers: headers
      expect(response).to have_http_status(:ok)
      expect(b.reload).to be_cancelled
    end

    it "denies cancel of other host's booking (403)" do
      other_host = create(:host)
      other_et = create(:event_type, host: other_host)
      other_b = create(:booking, host: other_host, event_type: other_et)
      delete "/bookings/#{other_b.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end
  end
end
