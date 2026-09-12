require "./spec_helper"

Spectator.describe Crystal::Roguelike do
  describe "VERSION" do
    it "matches the version in shard.yml" do
      expect(Crystal::Roguelike::VERSION).to match(/\A\d+\.\d+\.\d+/)
    end
  end
end
