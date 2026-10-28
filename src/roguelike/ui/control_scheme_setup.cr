require "../../crystal-roguelike"

module Roguelike::Ui
  # Applies and saves an explicit choice from the control comparison.
  class ControlSchemeSetup
    record Result, scheme : Options::ControlScheme?, saved : Bool = false,
      error : String? = nil do
      def accepted? : Bool
        !@scheme.nil?
      end
    end

    getter picker : ControlSchemePicker = ControlSchemePicker.new

    property root : Path

    property on_change : Proc(Options, Nil)? = nil

    def initialize(@root : Path = Submit.root)
    end

    def self.needed?(options : Options) : Bool
      !options.control_scheme_chosen?
    end

    # Calls *answered* after a choice is applied or the comparison is canceled.
    def show(app : Widgets::App, options : Options, &answered : Result -> Nil) : Nil
      @picker.on_choose = ->(scheme : Options::ControlScheme?) do
        if scheme
          options.control_scheme = scheme
          Options.current = options
          error = save options
          @on_change.try &.call options
          answered.call Result.new(scheme, error.nil?, error)
        else
          answered.call Result.new(nil)
        end
        nil
      end
      @picker.show app, options.control_scheme
    end

    private def save(options : Options) : String?
      options.write @root
      nil
    rescue error : IO::Error
      "The control scheme could not be saved. It applies for this session: #{error.message}"
    end
  end
end
