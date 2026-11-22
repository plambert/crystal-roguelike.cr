require "../../crystal-roguelike"

module Roguelike::Ui
  class Play
    # How far one movement key pans the map while the search shows its
    # matches there, in columns and rows.
    SEARCH_PAN = {4, 2}

    # The search panel. Built the first time `/` is pressed.
    @search_pane : ItemSearchPane? = nil

    # The bar along the top of the map while the matches show there.
    @search_bar : ItemSearchBar? = nil

    # Whether a search is open, in the panel or on the map.
    getter? searching : Bool = false

    # Whether the panel is down and the matches show on the map.
    getter? searching_map : Bool = false

    # What has been typed.
    getter search_query : String = ""

    # Every item remembered on the floor, nearest first, as of
    # `@search_turn` on `@search_floor`.
    @search_entries : Array(ItemSearch::Entry) = [] of ItemSearch::Entry
    @search_turn : Int32 = 0
    @search_floor : String = ""

    # The id of the item chosen in the panel. `nil` when none is.
    @search_chosen : Int32? = nil

    # Whether showing the map turned hover mode on, so leaving it turns it
    # off again.
    @search_forced_hover : Bool = false

    # Where the camera was when the search opened, and the turn it opened
    # on. Closing puts the camera back when no turn has passed.
    @search_camera : {Int32, Int32}? = nil
    @search_opened : Int32 = 0

    # The search panel.
    def search_pane : ItemSearchPane
      @search_pane ||= begin
        pane = ItemSearchPane.new
        pane.on_change = ->(text : String) { searched text; nil }
        pane.on_choose = ->(entry : ItemSearch::Entry?) { chose_found entry; nil }
        pane.on_map = -> { show_search_map; nil }
        pane.on_close = -> { close_search; nil }
        pane
      end
    end

    # The bar along the top of the map.
    def search_bar : ItemSearchBar
      @search_bar ||= begin
        bar = ItemSearchBar.new
        bar.on_click = -> { show_search_panel; nil }
        bar
      end
    end

    # The entries the search matches now, nearest first.
    def search_matches : Array(ItemSearch::Entry)
      ItemSearch.matching @search_entries, @search_query
    end

    # Opens the search panel. `/` does this.
    #
    # With the matches on the map, it brings the panel back. Nothing opens
    # while a box is up, while a command waits for a direction or a target,
    # or while the examine cursor is out.
    def open_search : Nil
      return show_search_panel if @searching_map
      return if @searching || modal? || @pending || @aiming || @examiner.cursoring?

      app = @app
      return unless app

      @searching = true
      @search_query = ""
      @search_chosen = nil
      @search_camera = @map.camera
      @search_opened = @game.turn
      drop_hover
      collect_found

      pane = search_pane
      pane.restyle
      pane.show app, @search_query
      fill_search
      chose_found pane.chosen
    end

    # Takes the panel down and shows every match on the map. `Tab`, `Enter`
    # and the panel's map button do this.
    #
    # Hover mode goes on, so pointing at a match shows what lies there.
    def show_search_map : Nil
      return if !@searching || @searching_map

      app = @app
      return unless app

      @searching_map = true
      search_pane.hide
      unless @hovering
        toggle_hover
        @search_forced_hover = true
      end

      search_bar.show app, @screen.map, @search_query, search_matches.size
      refresh
    end

    # Puts the panel back up over the map. `Tab`, `Escape`, `/` and a click
    # on the bar do this while the matches show on the map.
    def show_search_panel : Nil
      return unless @searching_map

      app = @app
      return unless app

      @searching_map = false
      search_bar.hide
      unforce_hover
      drop_hover
      collect_found unless found_current?

      pane = search_pane
      pane.show app, @search_query
      fill_search
      chose_found pane.chosen
    end

    # Closes the search and takes everything it drew off the map. `Escape`
    # does this from the panel.
    def close_search : Nil
      return unless @searching

      end_search
      refresh
    end

    # Whether the cell *x*, *y* of the buffer is on the bar along the top
    # of the map.
    def over_search_bar?(x : Int32, y : Int32) : Bool
      bar = @search_bar
      return false unless bar && bar.showing?

      bar.frame.contains? x, y
    end

    # Pans the map a step toward *direction* while the matches show on it.
    # Answers whether it did, which is when the movement keys belong to the
    # search.
    private def pan_search(direction : Direction) : Bool
      return false unless @searching_map
      return false if @pending || @aiming || @examiner.cursoring?

      scroll_map direction.dx * SEARCH_PAN[0], direction.dy * SEARCH_PAN[1]
      true
    end

    # Takes the matches off the map and puts the panel back, when they are
    # on the map. Answers whether it did. `Tab` and `Escape` ask this first.
    private def search_back : Bool
      return false unless @searching_map
      return false if @pending || @aiming

      show_search_panel
      true
    end

    # Closes the search without drawing the screen again.
    private def end_search : Nil
      @searching = false
      @searching_map = false
      @search_pane.try &.hide
      @search_bar.try &.hide
      unforce_hover
      @map.clear_found
      @examine.searching = ""
      @nearby.searching = ""
      @search_chosen = nil
      @pointing = nil
      stop_fading

      camera = @search_camera
      @search_camera = nil
      @map.camera = camera if camera && @game.turn == @search_opened
    end

    # Turns hover mode back off if showing the map turned it on.
    private def unforce_hover : Nil
      forced = @search_forced_hover
      @search_forced_hover = false
      toggle_hover if forced && @hovering
    end

    # Whether the entries were worked out on this turn and this floor.
    private def found_current? : Bool
      @search_turn == @game.turn && @search_floor == @game.floor.id
    end

    # Works out the entries again from what the character remembers now.
    private def collect_found : Nil
      @search_entries = ItemSearch.entries @game
      @search_turn = @game.turn
      @search_floor = @game.floor.id
    end

    # Answers what was typed.
    private def searched(text : String) : Nil
      @search_query = text
      fill_search
      chose_found search_pane.chosen
    end

    # Puts the matches in the panel, keeping the chosen item, and tells the
    # info panel what to list first.
    private def fill_search : Nil
      @examine.searching = @search_query
      @nearby.searching = @search_query
      search_pane.fill search_matches, @search_entries.size, @search_chosen
    end

    # Draws the way to *entry* and brings it into the part of the map the
    # panel leaves clear.
    private def chose_found(entry : ItemSearch::Entry?) : Nil
      @search_chosen = entry.try &.item.id
      stop_fading

      if entry
        point_at_found entry
        clear_of_search entry.spot
      else
        @pointing = nil
      end

      refresh
    end

    # Points the map at *entry*, along the route a travel command would
    # take. A square with no known way to it is lit alone.
    private def point_at_found(entry : ItemSearch::Entry) : Nil
      spot = entry.spot
      route = entry.steps ? @game.route_to(spot) : [] of {Int32, Int32}
      aim_at spot, route
    end

    # Moves the camera so *spot* shows beside the panel rather than behind
    # it. When the edge of the floor stops the camera, the panel moves to
    # the other edge of the screen instead.
    private def clear_of_search(spot : {Int32, Int32}) : Nil
      @map.center_on spot[0], spot[1] unless @map.screen_of(spot[0], spot[1])

      pane = search_pane
      return if beside_search? spot, pane

      pane.flip
      beside_search? spot, pane
    end

    # Slides the camera sideways until *spot* is clear of *pane*, as far as
    # the edges of the floor let it. Answers whether *spot* is clear.
    private def beside_search?(spot : {Int32, Int32}, pane : ItemSearchPane) : Bool
      cell = @map.screen_of spot[0], spot[1]
      return false unless cell

      area = pane.area
      gap = 2
      return true if cell[0] < area.x - gap || cell[0] >= area.right + gap

      shift = pane.right? ? cell[0] - (area.x - gap - 1) : cell[0] - (area.right + gap)
      camera = @map.camera
      @map.camera = {camera[0] + shift, camera[1]}

      cell = @map.screen_of spot[0], spot[1]
      !cell.nil? && (cell[0] < area.x - gap || cell[0] >= area.right + gap)
    end

    # Lights every match on the map while a search is open.
    #
    # A turn passing works the entries out again, because the character has
    # moved or seen more. A new floor, or the run ending, closes the search.
    private def show_found : Nil
      return @map.clear_found unless @searching

      if @game.over? || @search_floor != @game.floor.id
        end_search
        return
      end

      unless found_current?
        collect_found
        fill_search
        chosen = @search_chosen.try { |id| @search_entries.find(&.item.id.== id) }
        point_at_found chosen if chosen
        app = @app
        search_bar.show app, @screen.map, @search_query, search_matches.size if app && @searching_map
      end

      @map.find search_matches.map(&.spot)
    end
  end
end
