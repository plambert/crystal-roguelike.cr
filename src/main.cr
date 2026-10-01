require "./crystal-roguelike"

Roguelike::Replay::Log.always = Roguelike::Replay::Log.test_logs if Roguelike::TEST_BUILD

Roguelike::Cli.dispatch ARGV
