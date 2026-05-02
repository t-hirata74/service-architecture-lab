require "net/http"
require "json"

# ADR 0003 / 0004: ai-worker /synthesize/stream の SSE chunked response を
# Rails::Live を経由して frontend に proxy する.
#
# 役割:
# - ai-worker への HTTP request を投げ、chunked stream を 1 chunk ずつ消費
# - SSE event ("event: chunk" / "event: done") をパース
# - 受信した chunk text を **CitationValidator で検査**:
#     - 完全 marker → frontend に "event: chunk" を流しつつ, valid なら "event: citation",
#       invalid なら "event: citation_invalid" を注入
#     - 不完全 marker (chunk 境界またぎ) は validator 内 buffer に保持
# - ai-worker からの "event: citation" イベントは **無視** (Rails 側で chunk から再構築)
# - 完了時に done を流して response.stream を close
#
# Phase 4 では本クラスが信頼境界の中核. ai-worker からの payload を直接 frontend に
# 流さず、必ず Rails 内で 1 度パース・検査してから書き戻す.
class SseProxy
  class Error < StandardError; end

  # @param ai_worker_base [String] e.g. "http://localhost:8030"
  # @param stream_timeout [Float] read_timeout in seconds
  def initialize(ai_worker_base: ENV.fetch("AI_WORKER_URL", "http://localhost:8030"),
                 stream_timeout: 60.0)
    @base = ai_worker_base
    @stream_timeout = stream_timeout
  end

  # @param query_text [String]
  # @param passages [Array<Hash>] /extract の出力
  # @param allowed_source_ids [Array<Integer>]
  # @param response_stream [#write, #close] Rails の `response.stream` (or テスト用 IO)
  # @param hits_by_source_id [Hash{Integer => Hash}] hits 配列を source_id 引き dict に
  #        したもの (Citation の chunk_id を埋めるため)
  # @yield [event_name, data] frontend に書き出した event を tee する callback (任意)
  # @return [Hash] { body:, citations: [{marker:, source_id:, chunk_id:, position:, valid:}] }
  def stream(query_text:, passages:, allowed_source_ids:, response_stream:, hits_by_source_id: {})
    validator = CitationValidator.new(allowed_source_ids: allowed_source_ids)

    accumulated_body = +""
    confirmed_citations = []

    request_synthesize(query_text, passages, allowed_source_ids) do |event|
      case event[:event]
      when "chunk"
        text = event[:data]["text"].to_s
        safe_text, citations = validator.process_chunk(text)

        # ADR 0003: chunk text を frontend に転送 (event:chunk).
        # citation marker を含む場合もテキスト自体は素通し (本文には残す = ADR 0004).
        write_event(response_stream, "chunk", { text: safe_text, ord: event[:data]["ord"] })
        accumulated_body << safe_text

        # 各 citation を frontend に通知 (valid なら event:citation, invalid なら citation_invalid).
        # source_id から chunk_id を埋める (hits 由来).
        citations.each do |c|
          c[:chunk_id] = hits_by_source_id.dig(c[:source_id], :chunk_id)
          if c[:valid]
            write_event(response_stream, "citation", citation_event_payload(c))
            confirmed_citations << c
          else
            write_event(response_stream, "citation_invalid", { marker: c[:marker], source_id: c[:source_id], position: c[:position] })
          end
        end
      when "citation"
        # ai-worker からの citation event は **無視** (Rails 側で chunk から再構築する信頼境界).
      when "done"
        # 残った tail buffer を flush
        tail = validator.flush
        unless tail.empty?
          write_event(response_stream, "chunk", { text: tail, ord: -1 })
          accumulated_body << tail
        end
        break  # done を受けたら ai-worker の request loop を抜ける
      else
        # message / unknown event は無視
      end
    end

    write_event(response_stream, "done", { body_length: accumulated_body.length, citations_count: confirmed_citations.size })

    { body: accumulated_body, citations: confirmed_citations }
  end

  private

  def citation_event_payload(c)
    {
      marker: c[:marker],
      source_id: c[:source_id],
      chunk_id: c[:chunk_id],
      position: c[:position],
      valid: true
    }
  end

  def write_event(stream, name, data)
    payload = "event: #{name}\ndata: #{data.to_json}\n\n"
    stream.write(payload)
  end

  # ai-worker /synthesize/stream に POST し、SSE event を 1 件ずつ yield.
  def request_synthesize(query_text, passages, allowed_source_ids, &block)
    uri = URI.parse("#{@base}/synthesize/stream")
    http = Net::HTTP.new(uri.host, uri.port)
    http.open_timeout = 5.0
    http.read_timeout = @stream_timeout

    request = Net::HTTP::Post.new(uri.path,
                                  "Content-Type" => "application/json",
                                  "Accept" => "text/event-stream")
    request.body = {
      query_text: query_text,
      passages: passages,
      allowed_source_ids: allowed_source_ids
    }.to_json

    http.request(request) do |response|
      raise Error, "ai-worker /synthesize/stream returned #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      buffer = +""
      response.read_body do |chunk|
        buffer << chunk
        while (sep_idx = buffer.index("\n\n"))
          block_text = buffer[0...sep_idx]
          buffer = buffer[(sep_idx + 2)..] || +""
          parsed = parse_sse_block(block_text)
          if parsed
            yield parsed
            return if parsed[:event] == "done"  # done 受信で proxy 終了
          end
        end
      end
      # 末尾フラッシュ (\n\n 欠落対策)
      unless buffer.strip.empty?
        parsed = parse_sse_block(buffer)
        yield parsed if parsed
      end
    end
  rescue Errno::ECONNREFUSED, Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise Error, "ai-worker unreachable: #{e.message}"
  end

  def parse_sse_block(block)
    event_name = nil
    data_lines = []
    block.each_line do |raw|
      line = raw.chomp
      next if line.empty?
      next if line.start_with?(":")
      if line.start_with?("event:")
        event_name = line.sub(/^event:\s*/, "")
      elsif line.start_with?("data:")
        data_lines << line.sub(/^data:\s*/, "")
      end
    end
    return nil if data_lines.empty?

    { event: event_name || "message", data: JSON.parse(data_lines.join("\n")) }
  rescue JSON::ParserError => e
    raise Error, "malformed SSE data: #{e.message}"
  end
end
