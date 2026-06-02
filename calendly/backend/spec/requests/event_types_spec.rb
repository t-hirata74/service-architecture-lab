require "rails_helper"

RSpec.describe "EventTypes API", type: :request do
  let!(:auth) { signup_and_login(email: "host-et@example.com") }
  let(:host) { auth[0] }
  let(:headers) { auth[1] }

  describe "POST /event_types" do
    it "creates an event_type owned by current_host" do
      post "/event_types",
           params: { slug: "interview", title: "30 min interview",
                     duration_minutes: 30, max_advance_days: 60 }.to_json,
           headers: headers
      expect(response).to have_http_status(:created), response.body
      body = JSON.parse(response.body)
      expect(body["host_id"]).to eq(host.id)
      expect(body["slug"]).to eq("interview")
    end

    it "rejects unauthenticated requests with 401" do
      post "/event_types", params: { slug: "interview", title: "X",
                                      duration_minutes: 30 }.to_json,
                          headers: { "Content-Type" => "application/json" }
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PUT /event_types/:id" do
    let(:et) { create(:event_type, host: host) }

    it "updates own event_type" do
      put "/event_types/#{et.id}", params: { title: "Updated" }.to_json, headers: headers
      expect(response).to have_http_status(:ok), response.body
      expect(et.reload.title).to eq("Updated")
    end

    it "denies update on other host's event_type with 404 (host scoping)" do
      other_host = create(:host)
      other_et = create(:event_type, host: other_host)
      put "/event_types/#{other_et.id}", params: { title: "Hijack" }.to_json, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /event_types/:id/slots (public)" do
    let!(:rule) {
      create(:availability_rule, host: host,
             rrule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR",
             start_time_of_day: "09:00:00", end_time_of_day: "17:00:00",
             tz_id: "Asia/Tokyo")
    }
    let(:et) {
      create(:event_type, host: host, slug: "consult-30",
             duration_minutes: 60, before_buffer_minutes: 0, after_buffer_minutes: 0,
             min_notice_minutes: 0, max_advance_days: 365, active: true)
    }

    # 時刻依存を排除する。slots_service は effective_from = max(from, now + min_notice)
    # で過去を切り落とすため、ハードコードした window (2026-06-01 JST) より now が
    # 後ろへ回ると 0 件になり、実日付がこの日を過ぎた途端にテストが落ちていた。
    # now を window 前に固定し、カレンダー日付に依存せず安定して 8 スロット出す。
    around { |example| travel_to(Time.utc(2026, 5, 30, 0, 0, 0)) { example.run } }

    it "returns slots for active event_type without authentication" do
      get "/event_types/#{et.id}/slots",
          params: { from: "2026-05-31T15:00:00Z", to: "2026-06-01T15:00:00Z", tz: "America/New_York" }
      expect(response).to have_http_status(:ok), response.body
      body = JSON.parse(response.body)
      expect(body.size).to eq(8)  # 09:00-17:00 JST / 60 min slot = 8 個
      expect(body.first).to include("start_at_utc", "end_at_utc", "start_at_local")
    end

    it "returns 404 for inactive event_type" do
      et.update!(active: false)
      get "/event_types/#{et.id}/slots", params: { from: "2026-05-31T15:00:00Z", to: "2026-06-01T15:00:00Z" }
      expect(response).to have_http_status(:not_found)
    end

    # review fix C-A-2 / M-D-3: silent fallback ではなく 422 + errors 配列で集約する
    it "returns 422 collecting multiple errors (invalid from / invalid tz)" do
      get "/event_types/#{et.id}/slots", params: { from: "BOGUS", to: "2026-06-01T15:00:00Z", tz: "Mars/Olympus" }
      expect(response).to have_http_status(:unprocessable_entity)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("invalid_param")
      params = body["errors"].map { |e| e["param"] }
      expect(params).to include("from", "tz")
    end
  end
end
