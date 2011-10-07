local Events = require('events')

local emitter = Events.new_event_emitter()

emitter:on("foo", function (...)
  p("on_foo", ...)
end)

emitter:on("foo", function (...)
  p("on_foo2", ...)
end)

p(emitter)

emitter:emit("foo", 1, 2, 3)