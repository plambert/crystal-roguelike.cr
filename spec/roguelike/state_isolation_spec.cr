require "../spec_helper"

# The suite must never write the player's own state, so every default root
# is under the directory the spec helper made.
Spectator.describe "the suite's state directory" do
  it "holds Submit.root" do
    root = Roguelike::Submit.root
    expect(root.parents).to contain Path[SPEC_STATE_HOME]
    expect(root.to_s).to start_with Dir.tempdir
  end

  it "keeps Submit.root out of the player's own state directory" do
    {% if flag?(:win32) %}
      players = Path[ENV["LOCALAPPDATA"]? || Path.home.join("AppData", "Local").to_s, "roguelike"]
    {% else %}
      players = Path.home.join(".local", "state", "roguelike")
    {% end %}
    expect(Roguelike::Submit.root).not_to eq players
  end
end
