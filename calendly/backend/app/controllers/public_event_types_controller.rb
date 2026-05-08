# Phase 4-1: 公開予約ページ用エンドポイント。認証不要、event_type.active のみ表示。
class PublicEventTypesController < ApplicationController
  def show
    et = EventType.active.find_by(host_id: params[:host_id], slug: params[:slug])
    raise ActiveRecord::RecordNotFound if et.nil?

    render json: {
      id: et.id, host_id: et.host_id, slug: et.slug, title: et.title,
      duration_minutes: et.duration_minutes,
      host_name: et.host.name,
      slots_path: "/event_types/#{et.id}/slots"
    }
  end
end
