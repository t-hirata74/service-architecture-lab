require "rails_helper"

# MySQL InnoDB FULLTEXT インデックスはトランザクション内の INSERT を即時には
# 見えない (commit が必要)。RSpec のトランザクションフィクスチャを切って
# 自前で truncate する。
RSpec.describe "Videos search", type: :request do
  self.use_transactional_tests = false

  before(:all) do
    [Video, User, Tag, VideoTag].each(&:delete_all)
    @rails_video = create(:video, :published, title: "Rails 入門",          description: "rails ruby tutorial")
    @python_video = create(:video, :published, title: "Python レコメンダ",   description: "python ml ai")
    @ngram_video  = create(:video, :published, title: "MySQL ngram 全文検索", description: "database tutorial")
    @ready_only   = create(:video, :ready,     title: "公開前の Rails")
  end

  after(:all) do
    [Video, User, Tag, VideoTag].each(&:delete_all)
  end

  describe "GET /videos/search" do
    it "returns published videos matching the query" do
      get "/videos/search", params: { q: "rails" }
      expect(response).to have_http_status(:ok)
      assert_schema_conform(200)
      titles = response.parsed_body["items"].map { _1["title"] }
      expect(titles).to include("Rails 入門")
      expect(titles).not_to include("公開前の Rails") # ready は除外
    end

    it "supports Japanese keyword search via ngram" do
      get "/videos/search", params: { q: "全文検索" }
      titles = response.parsed_body["items"].map { _1["title"] }
      expect(titles).to include("MySQL ngram 全文検索")
    end

    it "returns empty for blank query" do
      get "/videos/search", params: { q: " " }
      expect(response).to have_http_status(:ok)
      assert_schema_conform(200)
      expect(response.parsed_body["items"]).to eq([])
    end

    it "strips boolean-mode operators that would crash the parser" do
      get "/videos/search", params: { q: "+rails" }
      expect(response).to have_http_status(:ok)
      assert_schema_conform(200)
      titles = response.parsed_body["items"].map { _1["title"] }
      expect(titles).to include("Rails 入門")
    end
  end
end
