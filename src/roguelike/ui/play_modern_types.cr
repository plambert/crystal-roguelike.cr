require "../../crystal-roguelike"

module Roguelike::Ui
  enum ModernChoiceKind
    Command
    Item
    Target
    Direction
    Empty
    MoreActions
    TitleNew
    TitleCharacter
    TitleOptions
    TitleNews
    TitleQuit
  end

  record ModernChoice,
    kind : ModernChoiceKind,
    command : Command? = nil,
    item_id : Int32? = nil,
    slot : Slot? = nil,
    direction : Direction? = nil,
    coordinate : {Int32, Int32}? = nil,
    character : String? = nil

  enum ModernMenuKind
    None
    Catalog
    Available
    Inventory
    ItemActions
    Targets
    Directions
    Title
  end

  record ModernMenuFrame,
    kind : ModernMenuKind,
    page : Int32 = 0,
    index : Int32? = nil,
    command : Command? = nil,
    item_id : Int32? = nil,
    slot : Slot? = nil,
    character : String? = nil
end
