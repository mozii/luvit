--[[

Copyright 2012 The Luvit Authors. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS-IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

--]]

-- Bootstrap require system
local native = require('uv_native')
process = {
  execPath = native.execpath(),
  cwd = getcwd,
  argv = argv
}
_G.getcwd = nil
_G.argv = nil
require = require('module').require

local Emitter = require('core').Emitter
local env = require('env')
local constants = require('constants')
local Tty = require('uv').Tty
local utils = require('utils')

setmetatable(process, Emitter.meta)

-- Replace lua's stdio with luvit's
-- leave stderr using lua's blocking implementation
process.stdin = Tty:new(0)
native.unref()
process.stdout = Tty:new(1)
native.unref()
process.stderr = io.stderr

-- clear some globals
-- This will break lua code written for other lua runtimes
_G.io = nil
_G.os = nil
_G.math = nil
_G.string = nil
_G.coroutine = nil
_G.jit = nil
_G.bit = nil
_G.debug = nil
_G.table = nil
_G.loadfile = nil
_G.dofile = nil
_G.print = utils.print
_G.p = utils.prettyPrint
_G.debug = utils.debug

-- Move the version variables into a table
process.version = VERSION
process.versions = {
  luvit = VERSION,
  uv = native.VERSION_MAJOR .. "." .. native.VERSION_MINOR .. "-" .. UV_VERSION,
  luajit = LUAJIT_VERSION,
  yajl = YAJL_VERSION,
  http_parser = HTTP_VERSION,
}
_G.VERSION = nil
_G.YAJL_VERSION = nil
_G.LUAJIT_VERSION = nil
_G.UV_VERSION = nil
_G.HTTP_VERSION = nil

-- Add a way to exit programs cleanly
function process.exit(exit_code)
  process:emit('exit', exit_code)
  exitProcess(exit_code or 0)
end

function process:addHandlerType(name)
  local code = constants[name]
  if code then
    native.activateSignalHandler(code)
    native.unref()
  end
end

function process:missingHandlerType(name, ...)
  if name == "error" then
    error(...)
  elseif name == "SIGINT" or name == "SIGTERM" then
    process.exit()
  end
end


-- Add global access to the environment variables using a dynamic table
process.env = setmetatable({}, {
  __pairs = function (table)
    local keys = env.keys()
    local index = 0
    return function (...)
      index = index + 1
      local name = keys[index]
      if name then
        return name, table[name]
      end
    end
  end,
  __index = function (table, name)
    return env.get(name)
  end,
  __newindex = function (table, name, value)
    if value then
      env.set(name, value, 1)
    else
      env.unset(name)
    end
  end
})

-- Copy date and time over from lua os module into luvit os module
local OLD_OS = require('os')
local OS_BINDING = require('os_binding')
package.loaded.os = OS_BINDING
package.preload.os_binding = nil
package.loaded.os_binding = nil
OS_BINDING.date = OLD_OS.date
OS_BINDING.time = OLD_OS.time


-- Ignore sigpipe and exit cleanly on SIGINT and SIGTERM
-- These shouldn't hold open the event loop
if OS_BINDING.type() ~= "win32" then
  native.activateSignalHandler(constants.SIGPIPE)
  native.unref()
  native.activateSignalHandler(constants.SIGINT)
  native.unref()
  native.activateSignalHandler(constants.SIGTERM)
  native.unref()
end

local traceback = require('debug').traceback

-- This is called by all the event sources from C
-- The user can override it to hook into event sources
function eventSource(name, fn, ...)
  local args = {...}
  return assert(xpcall(function ()
    return fn(unpack(args))
  end, traceback))
end


local function usage()
  print("Usage: " .. process.argv[0] .. " [options] script.lua [arguments]")
  print("")
  print("Options:")
  print("  -h, --help          Print this help screen.")
  print("  -v, --version       Print the version.")
  print("  -e code_chunk       Evaluate code chunk and print result.")
  print("  -i, --interactive   Enter interactive repl after executing script.")
  print("                      (Note, if no script is provided, a repl is run instead.)")
  print("")
end

local realAssert = assert
function assert(good, error)
  return realAssert(good, tostring(error))
end



assert(xpcall(function ()

  local interactive = false
  local showrepl = true
  local file
  local state = "BEGIN"
  local to_eval = {}
  local args = {[0]=process.argv[0]}


  for i, value in ipairs(process.argv) do
    if state == "BEGIN" then
      if value == "-h" or value == "--help" then
        usage()
        showrepl = false
      elseif value == "-v" or value == "--version" then
        print(process.version)
        showrepl = false
      elseif value == "-e" or value == "--eval" then
        state = "-e"
        showrepl = false
      elseif value == "-i" or value == "--interactive" then
        interactive = true
      elseif value:sub(1, 1) == "-" then
        usage()
        process.exit(1)
      else
        file = value
        showrepl = false
        state = "USERSPACE"
      end
    elseif state == "-e" then
      to_eval[#to_eval + 1] = value
      state = "BEGIN"
    elseif state == "USERSPACE" then
      args[#args + 1] = value
    end
  end

  if not (state == "BEGIN" or state == "USERSPACE") then
    usage()
    process.exit(1)
  end

  process.argv = args
  
  local repl = require('repl')

  for i, value in ipairs(to_eval) do
    repl.evaluateLine(value)
  end

  if file then
    assert(require('module').myloadfile(require('path').resolve(process.cwd(), file)))()
  elseif not (native.handleType(0) == "TTY") then
    process.stdin:on("data", function(line)
      repl.evaluateLine(line)
    end)
    process.stdin:readStart()
    native.run()
    process.exit(0)
  end

  if interactive or showrepl then
    repl.start()
  end

end, traceback))

-- Start the event loop
native.run()
-- trigger exit handlers and exit cleanly
process.exit(0)



