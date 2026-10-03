require "http/client"
require "openssl"
require "../../roguelike"

module Roguelike
  module Submit
    # The side of the upload protocol a game plays.
    #
    # Each piece of a parcel goes in two requests. The first asks the upload
    # URL for a presigned form for one file of one size. The second posts
    # the file to the address the answer names, as the form the answer
    # gives. The server decides every name; the client never chooses one.
    class Client
      include Outbox::Carrier

      # How long to wait to connect, and for an answer.
      CONNECT = 10.seconds
      ANSWER  = 10.seconds

      # How long a file upload may take in all.
      UPLOAD = 60.seconds

      # The upload URL.
      getter url : URI

      def initialize(url : String)
        @url = URI.parse url
      end

      # What the first request asks for.
      record Request, token : String, version : String, platform : String,
        log : String, seq : Int32, kind : String, size : Int64 do
        include JSON::Serializable
      end

      # What the first request is answered with.
      class Ticket
        include JSON::Serializable

        getter url : String
        getter fields : Hash(String, String)
        getter key : String
      end

      # Sends every piece of *parcel*, the log first and the meta last.
      def send(parcel : Parcel) : Nil
        parcel.pieces.each do |piece|
          raise Error.new "#{piece.kind} is #{piece.size} bytes, over the #{LIMIT} byte limit" if piece.size > LIMIT

          upload ticket(parcel, piece), piece
        end
      end

      # Asks for the form that takes *piece*.
      def ticket(parcel : Parcel, piece : Parcel::Piece) : Ticket
        request = Request.new TOKEN, parcel.meta.version, parcel.meta.platform,
          parcel.meta.log, parcel.seq, piece.kind, piece.size

        response = client(@url, ANSWER) do |http|
          http.post @url.request_target, HTTP::Headers{"Content-Type" => "application/json"}, request.to_json
        end
        raise Error.new "the upload server answered #{response.status_code} #{reason response}" unless response.status.success?

        Ticket.from_json response.body
      rescue error : IO::Error | OpenSSL::Error | JSON::Error | URI::Error
        raise Error.new "asking for an upload failed: #{error.message}"
      end

      # Posts *piece* as the form *ticket* gives.
      def upload(ticket : Ticket, piece : Parcel::Piece) : Nil
        target = URI.parse ticket.url
        body = IO::Memory.new
        headers = HTTP::Headers.new

        HTTP::FormData.build body do |form|
          headers["Content-Type"] = form.content_type
          ticket.fields.each { |name, value| form.field name, value }
          File.open piece.path do |file|
            form.file "file", file, HTTP::FormData::FileMetadata.new(filename: piece.path.basename)
          end
        end

        response = client(target, UPLOAD) do |http|
          http.post target.request_target, headers, body.to_s
        end
        return if response.status.success?

        raise Error.new "the upload was refused with #{response.status_code} #{reason response}"
      rescue error : IO::Error | OpenSSL::Error | URI::Error
        raise Error.new "the upload failed: #{error.message}"
      end

      # One connection to *uri*, with the timeouts set.
      private def client(uri : URI, wait : Time::Span, & : HTTP::Client -> HTTP::Client::Response) : HTTP::Client::Response
        HTTP::Client.new uri do |http|
          http.connect_timeout = CONNECT
          http.read_timeout = wait
          http.write_timeout = wait
          yield http
        end
      end

      # The first line of what the server said, for a message.
      private def reason(response : HTTP::Client::Response) : String
        response.body.lines.first?.try(&.strip.[0, 120]) || ""
      end
    end
  end
end
