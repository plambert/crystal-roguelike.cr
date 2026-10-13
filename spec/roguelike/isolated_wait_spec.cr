require "../spec_helper"
require "socket"

# Crystal 1.22.0 segfaults here without `src/roguelike/isolated_wait.cr`.
Spectator.describe Fiber::ExecutionContext::Isolated do
  it "waits to read after a write on the same socket" do
    server = TCPServer.new "127.0.0.1", 0
    client = TCPSocket.new "127.0.0.1", server.local_address.port
    peer = server.accept
    replies = 0

    context = Fiber::ExecutionContext::Isolated.new "request-reply" do
      buffer = Bytes.new 4
      20.times do
        client.write "ping".to_slice
        client.read_fully buffer
        replies += 1 if buffer == "pong".to_slice
      end
    end

    buffer = Bytes.new 4
    20.times do
      peer.read_fully buffer
      sleep 1.millisecond
      peer.write "pong".to_slice
    end

    context.wait
    expect(replies).to eq 20
  ensure
    peer.try &.close
    client.try &.close
    server.try &.close
  end
end
