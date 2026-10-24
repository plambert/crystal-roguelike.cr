require "../spec_helper"
require "../support/recording"

Spectator.describe Roguelike::Replay::PlaybackCursor do
  alias PlaybackCursor = Roguelike::Replay::PlaybackCursor
  alias Backfill = Roguelike::Replay::Backfill
  alias Export = Roguelike::Replay::Export
  alias Reading = Roguelike::Replay::Reading
  alias Replay = Roguelike::Replay
  alias Verifier = Roguelike::Replay::Verifier
  alias Viewer = Roguelike::Replay::Viewer

  # Performs every record in *reading* and returns the cursor at the end.
  def played(reading : Reading) : PlaybackCursor
    cursor = PlaybackCursor.new reading, Verifier.rebuild(reading.header)
    while step = cursor.advance
      raise "#{step.failure}" if step.failure
    end
    cursor
  end

  # The golden replay with a complete footer and an incomplete trailing line.
  def tailed(state : String? = nil, incomplete_footer : Bool = false) : Path
    source = Recording.read Recording.golden
    cursor = played source
    lines = File.read_lines Recording.golden

    if incomplete_footer
      lines.pop
      tail = %({"type":"footer")
    else
      footer = JSON.parse(lines.pop).as_h
      if state
        footer["state"] = JSON::Any.new state
        footer["turn"] = JSON::Any.new cursor.game.turn.to_i64
        footer["ending"] = JSON::Any.new cursor.game.outcome.to_s.downcase
      end
      lines << footer.to_json
      tail = %({"type":"act")
    end

    where = Recording.directory / "tailed-#{Random.rand UInt32}.jsonl"
    File.write where, lines.join('\n') + "\n" + tail
    where
  end

  # Rebuilds *path* as events and answers the backfill report.
  def backfill(path : Path) : Backfill::Report
    target = Recording.directory / "backfilled-#{Random.rand UInt32}.events.jsonl.gz"
    Backfill.run path, target
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

  it "validates a retained footer after an incomplete trailing line" do
    path = tailed Recording.read(Recording.golden).header.state
    reading = Reading.read path
    viewer = Viewer.open path

    expect(reading.truncated?).to be_true
    expect(reading.footer.try(&.state)).to eq reading.header.state
    expect(Verifier.check(path).ok?).to be_false
    expect(Export.run(path, IO::Memory.new).ok?).to be_false
    expect(backfill(path).status).to eq(Backfill::DIFFERS)

    begin
      viewer.goto viewer.size
      expect(viewer.trouble.to_s).to contain "the run ends differently"
    ensure
      viewer.close
    end
  end

  it "accepts a correct retained footer after an incomplete trailing line" do
    source = Recording.read Recording.golden
    cursor = played source
    state = cursor.game.fingerprint like: source.header.state
    path = tailed state
    reading = Reading.read path
    viewer = Viewer.open path

    expect(reading.truncated?).to be_true
    expect(reading.footer.try(&.state)).to eq state
    expect(Verifier.check(path).ok?).to be_true
    expect(Export.run(path, IO::Memory.new).ok?).to be_true
    expect(backfill(path).ok?).to be_true

    begin
      viewer.goto viewer.size
      expect(viewer.trouble).to be_nil
    ensure
      viewer.close
    end
  end

  it "accepts a crash with no complete footer" do
    path = tailed incomplete_footer: true
    reading = Reading.read path
    viewer = Viewer.open path

    expect(reading.truncated?).to be_true
    expect(reading.footer).to be_nil
    expect(Verifier.check(path).ok?).to be_true
    expect(Export.run(path, IO::Memory.new).ok?).to be_true
    expect(backfill(path).ok?).to be_true

    begin
      viewer.goto viewer.size
      expect(viewer.trouble).to be_nil
    ensure
      viewer.close
    end
  end
end
