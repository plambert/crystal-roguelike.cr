require "json"
require "../roguelike"

module Roguelike
  # A JSON converter that writes a `Hash` or a `Set` in a fixed order for a
  # streamed fingerprint.
  #
  # A `Hash` and a `Set` write their entries in the order they were filled.
  # While `Fingerprint.streaming?` is set, this writes a hash's entries in
  # order by the name each key is written under, and a set's elements in
  # their own order. What is written then depends on what the collection
  # holds and not on how it was filled.
  #
  # Every other write, a save included, is the one `T` makes itself. A set
  # is a JSON array, and the canonical fingerprint keeps an array's order.
  # Sorting it there would change values that earlier builds recorded.
  #
  # *T* is the type of the field. A field takes it with one annotation.
  # Name every type in it in full. The annotation is also expanded outside
  # the class it sits in, and a short name does not resolve there.
  #
  # ```
  # @[JSON::Field(converter: Roguelike::Sorted(Hash(String, Roguelike::Fixture)))]
  # getter fixtures : Hash(String, Fixture)
  # ```
  #
  # Reading is unchanged. A sorted order is still an order `T.new` reads.
  module Sorted(T)
    def self.from_json(pull : JSON::PullParser) : T
      T.new pull
    end

    def self.to_json(value : Hash, json : JSON::Builder) : Nil
      return value.to_json(json) unless Roguelike::Fingerprint.streaming?

      entries = value.map { |key, item| {key.to_json_object_key, item} }

      # No two keys of one hash are written under the same name, so no two
      # entries compare equal and an unstable sort leaves one order.
      entries.unstable_sort! { |one, other| one[0] <=> other[0] }

      json.object do
        entries.each do |(name, item)|
          json.field(name) { item.to_json json }
        end
      end
    end

    def self.to_json(value : Set, json : JSON::Builder) : Nil
      return value.to_json(json) unless Roguelike::Fingerprint.streaming?

      json.array do
        value.to_a.unstable_sort!.each &.to_json(json)
      end
    end
  end
end
