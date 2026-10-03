require "../../roguelike"

module Roguelike
  module Submit
    # Where replay logs are sent.
    #
    # It is the upload URL the server repository writes to `upload-url.txt`
    # when the stack is deployed. Empty means this binary sends nowhere, and
    # parcels wait in the outbox. `--submit-url` names another for a run.
    ENDPOINT = "https://24uzfbfq355lfhscjikcbmftqu0ngjkb.lambda-url.us-west-2.on.aws/"
  end
end
