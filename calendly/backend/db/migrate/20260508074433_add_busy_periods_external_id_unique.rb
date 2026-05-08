# review fix I-C-2: 外部カレンダー (Google / Outlook 等) からの再取込で重複を作らないため、
# (host_id, external_id) を UNIQUE にする。
# MySQL では UNIQUE index 内で NULL は複数行許容される (SQL 標準のとおり) ため、
# external_id が NULL の手動エントリは何件でも作成可能。
# 同じ host が同じ Google event を 2 回取込もうとした場合だけ ActiveRecord::RecordNotUnique で弾かれる。
class AddBusyPeriodsExternalIdUnique < ActiveRecord::Migration[8.1]
  def change
    add_index :busy_periods, [ :host_id, :external_id ],
              unique: true,
              name: "index_busy_periods_on_host_external_unique"
  end
end
