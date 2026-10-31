require "../../crystal-roguelike"

module Roguelike::Ui
  class Play
    # ------------------------------------------------------------- food bag

    # The key the inventory row for the food bag answers to.
    FOOD_BAG_KEY = '%'

    # The title of the food bag screen.
    FOOD_BAG = "Food bag"

    # Which sort the food bag screen opened on last.
    @food_sort : Int32 = 0

    # What runs when the food bag screen is closed. `nil` goes back to the
    # map.
    @food_back : Proc(Nil)? = nil

    # What the food bag holds, written for a row in the inventory. The blank
    # field in front lines it up with the names above it.
    def food_bag_summary : String
      bag = @game.player.food_bag
      "#{" " * Naming::LEAD} food bag #{bag.weight}/#{FoodBag::LIMIT}"
    end

    # The inventory row that opens the food bag.
    def food_bag_entry : Widgets::Menu::Entry
      Widgets::Menu::Entry.new FOOD_BAG_KEY, food_bag_summary, mark: ' '
    end

    # Shows what is in the food bag, and any corpse underfoot. `e` does
    # this.
    #
    # One page per sort, and the left and right keys turn the page. A row's
    # letter stays with its food on every page. A letter puts up what can
    # be done with that food. *back* runs when the screen is closed.
    def show_food_bag(back : Proc(Nil)? = nil) : Nil
      @food_back = back
      found = food_rows
      if found.empty?
        say "Your food bag is empty and there is nothing here to eat."
        finish_food
        return
      end

      pages = FoodSort.values.map do |sort|
        {sort.label, food_page(found, sort)}
      end
      about = {} of Char => Listing
      found.each { |key, item| about[key] = Listing.new key, item }

      title = "#{FOOD_BAG} #{@game.player.food_bag.weight}/#{FoodBag::LIMIT}"
      choose(title, pages, @food_sort.clamp(0, pages.size - 1), about) do |key|
        @food_sort = @menu.page
        item = key ? found.find(&.[0].==(key)).try(&.[1]) : nil
        if item
          act_on_food item
        else
          finish_food
        end
      end
    end

    # The food the screen lists, each under its letter: the bag in the
    # order it was filled, then each corpse underfoot.
    private def food_rows : Array({Char, Item})
      held = @game.player.food_bag.items.dup
      @game.here.each { |item| held << item if item.corpse? }
      held.map_with_index { |item, index| {Widgets::Menu.letter(index), item} }
    end

    # *found* as rows, in the order *sort* puts them.
    #
    # A row is the name, which says when a food is stale, rotten or partly
    # eaten, and what the stack weighs. A corpse underfoot has no weight,
    # because it does not go in the bag.
    private def food_page(found : Array({Char, Item}), sort : FoodSort) : Array(Widgets::Menu::Entry)
      bag = FoodBag.new found.map(&.[1]).reject(&.corpse?)
      ordered = bag.sorted(sort).compact_map { |item| found.find(&.[1].same?(item)) }
      ordered.concat found.select(&.[1].corpse?)

      nouns = ordered.map { |(_key, item)| Naming.listed @game.lore, item }
      leads = ordered.map { |(_key, item)| Naming.lead @game.lore, item }
      lead = Math.max leads.max_of?(&.size) || 0, Naming::LEAD
      noun = nouns.max_of?(&.size) || 0

      ordered.map_with_index do |(key, item), index|
        weight = item.corpse? ? "" : item.weight.to_s
        text = "#{leads[index].rjust(lead)} #{nouns[index].ljust(noun)} #{weight.rjust(2)}"
        Widgets::Menu::Entry.new key, text.rstrip, mark: ' '
      end
    end

    # Puts up what can be done with *item*: eat it, cut it up, or drop it.
    #
    # Each row is dimmed where it does not apply, so a key is in the same
    # place every time. `Escape` goes back to the bag.
    private def act_on_food(item : Item) : Nil
      corpse = item.corpse?
      entries = [
        Widgets::Menu::Entry.new('e', "eat", enabled: @game.edible.any?(&.same?(item))),
        Widgets::Menu::Entry.new('c', "cut up", enabled: @game.cuttable.any?(&.same?(item))),
        Widgets::Menu::Entry.new('d', "drop", enabled: !corpse),
      ]
      about = {} of Char => Listing
      entries.each { |entry| about[entry.key] = Listing.new entry.key, item }

      choose(Lore.sentence(@game.name(item)), entries, about) do |key|
        case key
        when 'e' then @game.perform Action::Eat.new(item.id)
        when 'c' then @game.perform Action::Cut.new(item.id)
        when 'd' then @game.perform Action::Drop.new(item.id)
        else
          show_food_bag @food_back
          next
        end

        @food_back = nil
        clear_modern_menu if modern_controls?
        refresh
      end
    end

    # Closes the food bag screen and runs what it goes back to.
    private def finish_food : Nil
      back = @food_back
      @food_back = nil
      return back.call if back

      refresh
    end
  end
end
