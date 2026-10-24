require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay::PlaybackCursor do
  alias PlaybackCursor = Roguelike::Replay::PlaybackCursor
  alias Reading = Roguelike::Replay::Reading
  alias Replay = Roguelike::Replay
  alias Verifier = Roguelike::Replay::Verifier

  # Performs every record in *reading* and returns the cursor at the end.
  def played(reading : Reading) : PlaybackCursor
    cursor = PlaybackCursor.new reading, Verifier.rebuild(reading.header)
    while step = cursor.advance
      raise "#{step.failure}" if step.failure
    end
    cursor
  end

  it "rewinds a resumed run to its saved pause" do
    source = Recording.read Recording.golden
    actions = source.records.compact_map(&.as?(Replay::Act))
    game = Verifier.rebuild source.header
    game.perform actions.first.action
    game.look

    at = Time.utc
    state = game.fingerprint
    pause = Replay::Pause.new 1, game.turn, state, at
    resume = Replay::Resume.new 1, game.turn, state, at, Roguelike::VERSION
    records = [actions[0], pause, actions[1], resume, actions[1]] of Replay::Record
    reading = Reading.new Path["cursor"], source.header, records, nil, false, 0
    cursor = PlaybackCursor.new reading, Verifier.rebuild(source.header)

    while step = cursor.advance
      expect(step.failure).to be_nil
      expect(cursor.game.turn).to eq pause.turn if step.record.is_a?(Replay::Resume)
    end

    expect(cursor.game.turn).to be > pause.turn
  end

  it "accepts an exit footer without a final fingerprint" do
    reading = Recording.read Recording.golden
    cursor = played reading

    expect(reading.footer.try(&.state)).to be_nil
    expect(cursor.finish).to be_nil
  end

  it "ignores a footer after a crash-truncated final line" do
    source = Recording.read Recording.golden
    original = source.footer.as Replay::Footer
    wrong = Replay::Footer.new original.turn, original.outcome, original.ending,
      original.ended_at, source.header.state, original.cause
    reading = Reading.new source.path, source.header, source.records, wrong,
      true, source.ignored
    cursor = played reading

    expect(cursor.finish).to be_nil
    expect(PlaybackCursor.footer(reading, cursor.game)).to be_nil
  end
end
