require "rails_helper"

# Phase 4-1: 会議ライフサイクル REST API の request spec。
RSpec.describe "Meetings", type: :request do
  describe "POST /meetings" do
    it "認証なしでは 401" do
      post "/meetings", params: { title: "x", scheduled_start_at: 1.hour.from_now }, as: :json
      expect(response.status).to eq(401)
    end

    it "認証付きでは 201 + scheduled で作成" do
      _, headers = create_authenticated_user

      post "/meetings",
           params: { title: "Weekly sync", scheduled_start_at: 1.hour.from_now.iso8601 },
           headers: headers,
           as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["status"]).to eq("scheduled")
      expect(body["title"]).to eq("Weekly sync")
    end
  end

  describe "POST /meetings/:id/open" do
    it "host だけが open できる (ADR 0002)" do
      host, host_headers = create_authenticated_user
      _, other_headers = create_authenticated_user

      meeting = Meeting.create!(host: host, title: "T", scheduled_start_at: 1.hour.from_now)

      post "/meetings/#{meeting.id}/open", headers: other_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/meetings/#{meeting.id}/open", headers: host_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(meeting.reload.status).to eq("waiting_room")
    end
  end

  describe "POST /meetings/:id/end → FinalizeRecordingJob enqueue" do
    it "host が end するとジョブが積まれ ended に遷移する" do
      host, host_headers = create_authenticated_user
      meeting = Meeting.create!(
        host: host, title: "T",
        status: "live", started_at: 5.minutes.ago,
        scheduled_start_at: 1.hour.ago
      )

      ActiveJob::Base.queue_adapter = :test

      expect {
        post "/meetings/#{meeting.id}/end", headers: host_headers, as: :json
      }.to have_enqueued_job(FinalizeRecordingJob).with(meeting.id)

      expect(response).to have_http_status(:ok)
      expect(meeting.reload.status).to eq("ended")
    ensure
      ActiveJob::Base.queue_adapter = :solid_queue
    end
  end

  describe "POST /meetings/:id/transfer_host (ADR 0002)" do
    it "host のみが譲渡できる、譲渡対象は live participant でなければならない" do
      host, host_headers = create_authenticated_user
      target, _ = create_authenticated_user
      stranger, stranger_headers = create_authenticated_user

      meeting = Meeting.create!(
        host: host, title: "T",
        status: "live", started_at: 5.minutes.ago,
        scheduled_start_at: 1.hour.ago
      )
      Participant.create!(meeting: meeting, user: target, status: "live", joined_at: 1.minute.ago)

      # stranger は forbidden
      post "/meetings/#{meeting.id}/transfer_host",
           params: { to_user_id: target.id }, headers: stranger_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      # host が譲渡 → 200 + host_id 更新 + 履歴 1 件
      expect {
        post "/meetings/#{meeting.id}/transfer_host",
             params: { to_user_id: target.id }, headers: host_headers, as: :json
      }.to change { HostTransfer.count }.by(1)

      expect(response).to have_http_status(:ok)
      expect(meeting.reload.host_id).to eq(target.id)
    end

    it "non-live-participant への譲渡は 422" do
      host, host_headers = create_authenticated_user
      ghost = create(:user)
      meeting = Meeting.create!(
        host: host, title: "T",
        status: "live", started_at: 5.minutes.ago,
        scheduled_start_at: 1.hour.ago
      )

      post "/meetings/#{meeting.id}/transfer_host",
           params: { to_user_id: ghost.id }, headers: host_headers, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "POST /meetings/:id/admit (ADR 0002: co_host にも委譲)" do
    it "co_host は admit できる、stranger は 403" do
      host, host_headers = create_authenticated_user
      co_host, co_host_headers = create_authenticated_user
      participant = create(:user)
      stranger, stranger_headers = create_authenticated_user

      meeting = Meeting.create!(
        host: host, title: "T",
        status: "waiting_room", scheduled_start_at: 1.hour.from_now
      )
      MeetingCoHost.create!(meeting: meeting, user: co_host, granted_by_user: host)
      Participant.create!(meeting: meeting, user: participant, status: "waiting")

      post "/meetings/#{meeting.id}/admit",
           params: { user_id: participant.id }, headers: stranger_headers, as: :json
      expect(response).to have_http_status(:forbidden)

      post "/meetings/#{meeting.id}/admit",
           params: { user_id: participant.id }, headers: co_host_headers, as: :json
      expect(response).to have_http_status(:ok)
      expect(meeting.reload.status).to eq("live")
    end
  end

  describe "GET /meetings/:id/summary" do
    it "summary が無いと 404" do
      host, host_headers = create_authenticated_user
      meeting = Meeting.create!(host: host, title: "T", status: "ended",
                                scheduled_start_at: 1.hour.ago, started_at: 1.hour.ago, ended_at: 30.minutes.ago)

      get "/meetings/#{meeting.id}/summary", headers: host_headers
      expect(response).to have_http_status(:not_found)
    end

    it "summary があれば body を返す" do
      host, host_headers = create_authenticated_user
      meeting = Meeting.create!(host: host, title: "T", status: "summarized",
                                scheduled_start_at: 1.hour.ago, started_at: 1.hour.ago, ended_at: 30.minutes.ago)
      Summary.create!(meeting: meeting, body: "the body", input_hash: "h", generated_at: Time.current)

      get "/meetings/#{meeting.id}/summary", headers: host_headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["body"]).to eq("the body")
    end
  end
end
