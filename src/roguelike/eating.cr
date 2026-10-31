require "../roguelike"

module Roguelike
  class Game
    # ----------------------------------------------------------------- food

    # Puts food about *ground*, on a stream of its own, and gives it ids.
    #
    # The stream is named by the floor, so the litter and the ammunition
    # fall where they always fell. Each food comes out somewhere between
    # just made and just short of stale.
    #
    # It runs once everything else on the floor has its id. The food takes
    # the ids after them, so nothing else is numbered differently for it.
    def stock(rng : Rng, ground : Floor = floor) : Nil
      stream = rng.derive "pantry:#{ground.id}"
      squares = [] of {Int32, Int32}
      ground.each { |column, row, tile| squares << {column, row} if tile.terrain.floor? }
      return if squares.empty?

      Math.max(squares.size * Food::PER_TEN_THOUSAND // 10_000, 1).times do
        spot = squares.sample stream
        kind = Items.pick stream, Food::LITTER
        keeps = Food.facts(kind).keeps
        age = keeps > 0 ? stream.rand(keeps) : 0
        made = Item.new kind, blessing_known: true, age: age
        made.enroll next_id
        ground.drop spot[0], spot[1], made
      end
      clear_bearers
    end

    # Puts what *creature* leaves on the square it died on.
    #
    # *shown* says the character saw it die, and only then is there an
    # event.
    private def leave_remains(creature : Monster, shown : Bool) : Nil
      left = Game.remains_of creature.kind
      return if left.empty?

      left.each do |item|
        item.enroll next_id
        floor.drop creature.x, creature.y, item
      end
      return unless shown

      record Event::CorpseLeft.new(creature.id, left.map(&.id), creature.at)
    end

    # What a creature of *kind* leaves where it dies.
    def self.remains_of(kind : Kind) : Array(Item)
      case kind.remains
      in .nothing? then [] of Item
      in .corpse?  then [Item.new(ItemKind::Corpse, blessing_known: true, creature: kind)]
      in .flesh_and_bones?
        [Item.new(ItemKind::RottenFlesh, blessing_known: true),
         Item.new(ItemKind::Bones, blessing_known: true)]
      in .bones? then [Item.new(ItemKind::Bones, blessing_known: true)]
      end
    end

    # Ages the food in the bag and on this floor, rots corpses away, and
    # counts the buffs down. `#tick` calls this once a turn.
    #
    # Other floors wait for the character, the way their creatures do.
    private def keep_food : Nil
      @player.food_bag.ripen.each { |item| spoiled item }
      age_the_floor
      @player.pass_buffs.each { |status| buff_ended status }
    end

    # Says that *item* in the bag has gone stale or rotten.
    #
    # An explore and a travel go on past the line. `#told?` overlooks it.
    private def spoiled(item : Item) : Nil
      wrote = @log.written
      noun = name item
      verb = item.count > 1 ? "have" : "has"
      say "#{Lore.sentence noun} in your food bag #{verb} gone #{item.freshness.label}.",
        Event::FoodSpoiled.new(item.id, noun, item.freshness)
      @overlooked += @log.written - wrote
    end

    # Ages every food lying on this floor, and takes away each corpse that
    # has rotted.
    private def age_the_floor : Nil
      rotted = [] of {Int32, Int32, Item}

      floor.each_pile do |column, row, pile|
        pile.each do |item|
          next unless item.food?

          item.ripen
          rotted << {column, row, item} if item.corpse? && item.freshness.rotten?
        end
      end

      rotted.each do |column, row, item|
        next unless floor.take column, row, item

        clear_bearers
        record Event::CorpseRotted.new(item.id, {column, row}) if can_see? column, row
      end
    end

    # Says that the buff *status* has worn off.
    private def buff_ended(status : Event::Status) : Nil
      line = case status
             when .well_fed?    then "The meal you ate no longer quickens you."
             when .refreshed?   then "The fruit you ate wears off."
             when .steady_aim?  then "Your aim is no longer as steady."
             when .steady_hand? then "Your hand is no longer as steady."
             when .sick?        then "You feel better."
             else                    "An effect wears off."
             end
      say line, Event::StatusEnd.new(status)
    end

    # Takes up to *points* of satiety. Answers how many were taken.
    private def satisfy(points : Int32) : Int32
      @player.sustenance.eat points
    end

    # The food the character can eat now: what is in the bag, and a corpse
    # underfoot that has not rotted.
    def edible : Array(Item)
      found = @player.food_bag.items.select &.edible?
      here.each { |item| found << item if item.corpse? && !item.freshness.rotten? }
      found
    end

    # Whether thirst holds still this turn. Fruit makes it build at half
    # rate, so it holds on every other turn while `Refreshed` runs.
    private def thirst_held? : Bool
      @player.buff_power(Event::Status::Refreshed) > 0 && @turn.odd?
    end

    # Whether the food bag holds anything or a corpse lies underfoot.
    def food_at_hand? : Bool
      !@player.food_bag.empty? || here.any?(&.corpse?)
    end

    # The corpses underfoot fresh enough to cut up.
    def cuttable : Array(Item)
      here.select { |item| item.corpse? && item.freshness.fresh? }
    end

    # Eats *item*, from the bag or from a corpse underfoot. Answers whether
    # any of it was eaten.
    #
    # Eating stops when the character is full. A partly eaten item keeps
    # what is left. Nothing eaten leaves everything as it was and spends no
    # turn.
    def eat(item : Item) : Bool
      noun = name item
      unless item.edible?
        say "You cannot eat #{noun}.",
          Event::Refused.new(:not_edible, item: item.id, name: noun)
        return false
      end

      offered = item.nourishment
      taken = offered > 0 ? satisfy(offered) : 0
      if taken <= 0
        say "You are too full to eat.", Event::Refused.new(:full, item: item.id, name: noun)
        return false
      end

      freshness = item.freshness
      category = item.category
      eaten = the item.with_count(1)
      whole = taken >= offered
      one = item.corpse? ? item : (@player.food_bag.take_one(item, next_id) || item)
      kept = one.bite(taken) && !whole
      eaten_id = one.id
      put_away one, kept

      @pack_moves += 1
      line = whole ? "You eat #{eaten}." : "You eat some of #{eaten} and are full."
      say line, Event::Ate.new(eaten_id, eaten, taken, whole)
      nourished category, freshness
      spend_turn
      true
    end

    # Puts what is left of *one* back, or takes it away when it is all
    # eaten.
    private def put_away(one : Item, kept : Bool) : Nil
      if one.corpse?
        floor.take @player.x, @player.y, one unless kept
        clear_bearers
        return
      end

      @player.food_bag.put_back one if kept
      clear_bearers
    end

    # Gives what eating food of *category* at *freshness* gives.
    #
    # Fresh food gives its buff whole. Stale food gives half of it, and a
    # half that rounds to nothing is no buff. Rotten food makes the
    # character sick.
    private def nourished(category : FoodCategory, freshness : Freshness) : Nil
      if freshness.rotten?
        offer_buff Event::Status::Sick, Food::SICK_AIM, Food::SICK_TURNS
        return
      end

      status = category.buff
      return unless status

      power = Game.buff_power status
      power //= 2 if freshness.stale?
      return if power <= 0

      offer_buff status, power, Food::BUFF_TURNS
    end

    # How strong the buff *status* is from fresh food.
    def self.buff_power(status : Event::Status) : Int32
      case status
      when .well_fed?                  then Food::PACE
      when .steady_aim?, .steady_hand? then Food::AIM
      else                                  1
      end
    end

    # Offers the buff *status* and says what came of it.
    private def offer_buff(status : Event::Status, power : Int32, turns : Int32) : Nil
      taken = @player.buff status, power, turns
      return if taken.weaker?

      again = !taken.started?
      say buff_line(status, again), Event::StatusStart.new(status, again: again)
    end

    # What the character is told when the buff *status* starts.
    private def buff_line(status : Event::Status, again : Bool) : String
      case status
      when .well_fed?    then again ? "You feel well fed again." : "You feel well fed and quick on your feet."
      when .refreshed?   then again ? "The fruit refreshes you again." : "The fruit refreshes you."
      when .steady_aim?  then again ? "Your aim feels steady again." : "Your aim feels steady."
      when .steady_hand? then again ? "Your hand feels steady again." : "Your hand feels steady."
      when .sick?        then again ? "You feel sicker." : "You feel sick."
      else                    "You feel different."
      end
    end

    # Cuts the corpse *item* underfoot into meat for the bag. Answers
    # whether it was cut.
    #
    # A corpse of each size cuts into `Food::CUTS` pieces, fewer for one
    # partly eaten. What the bag has no room for stays on the floor.
    def cut(item : Item) : Bool
      noun = the item
      unless item.freshness.fresh?
        say "#{Lore.sentence noun} is too far gone to cut up.",
          Event::Refused.new(:too_old, item: item.id, name: noun)
        return false
      end

      full = item.full_satiety
      pieces = Math.max (Food::CUTS[item.size] * item.satiety + full - 1) // full, 1
      floor.take @player.x, @player.y, item

      kept = [] of Int32
      left = [] of Int32
      pieces.times do
        meat = Item.new ItemKind::FreshMeat, blessing_known: true
        meat.enroll next_id
        held = @player.food_bag.add meat
        if held
          kept << held.id unless kept.includes? held.id
        else
          floor.drop @player.x, @player.y, meat
          left << meat.id
        end
      end

      @pack_moves += 1
      clear_bearers
      say cut_line(noun, kept.size, left.size),
        Event::Butchered.new(item.id, noun, kept, left)
      spend_turn
      true
    end

    # What cutting up a corpse says.
    private def cut_line(noun : String, kept : Int32, left : Int32) : String
      cut = "You cut up #{noun}"
      return "#{cut} and put the meat in your food bag." if left.zero?
      return "#{cut}, but your food bag has no room for the meat." if kept.zero?

      "#{cut}. Your food bag has no room for some of the meat."
    end

    # Puts *item*, already taken off the floor, in the food bag. Answers
    # whether it went in.
    #
    # A corpse is too big and goes back where it was, and so does anything
    # the bag has no room for.
    private def bag(item : Item) : Bool
      noun = name item
      if item.corpse?
        floor.drop @player.x, @player.y, item
        say "#{Lore.sentence the(item)} is too big for your food bag. You can eat it or cut it up.",
          Event::Refused.new(:too_big, item: item.id, name: noun)
        return false
      end

      left = item.dropped?
      item.take_up
      held = @player.food_bag.add item
      unless held
        item.set_down if left
        floor.drop @player.x, @player.y, item
        say "Your food bag has no room for #{noun}.",
          Event::Refused.new(:bag_full, item: item.id, name: noun)
        return false
      end

      @pack_moves += 1
      say "You put #{noun} in your food bag.",
        with_facts(Event::PickedUp.new(held.id, noun), item_facts(item))
      spend_turn
      true
    end

    # Puts the stack *item* from the food bag on the floor.
    def drop_food(item : Item) : Bool
      return false unless @player.food_bag.remove item

      noun = name item
      item.set_down
      floor.drop @player.x, @player.y, item
      @pack_moves += 1
      say "You drop #{noun}.", Event::Dropped.new([item.id], noun)
      spend_turn
      true
    end

    # Whether automatic pickup puts *item* in the food bag.
    #
    # Food that has not rotted and fits. Nothing the character put down,
    # no corpse, and none of the refuse.
    private def bag_takes?(item : Item) : Bool
      item.edible? && !item.corpse? && !item.freshness.rotten? &&
        !item.dropped? && @player.food_bag.room_for?(item)
    end

    # The verbs that eat and cut up food.
    private def feeding(action : Action::Eat | Action::Cut) : Verdict
      case action
      in Action::Eat
        item = @player.food_bag[action.item] ||
               here.find { |lying| lying.corpse? && lying.id == action.item }
        return Verdict.refused unless item && edible.any?(&.same?(item))

        eat item
        Verdict.done
      in Action::Cut
        item = cuttable.find &.id.==(action.item)
        return Verdict.refused unless item

        cut item
        Verdict.done
      end
    end

    # What the food bag and the corpses underfoot offer.
    private def legal_food(found : Array(Action)) : Nil
      edible.each { |item| found << Action::Eat.new item.id }
      cuttable.each { |item| found << Action::Cut.new item.id }
      @player.food_bag.items.each { |item| found << Action::Drop.new item.id }
    end
  end
end
