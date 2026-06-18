ExUnit.start()
Mox.defmock(Tink.HTTP.Mock, for: Tink.HTTP.Behaviour)
# config/test.exs sets http_adapter: Tink.HTTP.Mock so no override needed here
