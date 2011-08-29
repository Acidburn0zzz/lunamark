-- (c) 2009-2011 John MacFarlane. Released under MIT license.
-- See the file LICENSE in the source for details.

module("lunamark.writer.html5", package.seeall)

local util = require("lunamark.util")
local html = require("lunamark.writer.html")
local format = string.format

function new()
  local Html5 = html.new()

  function Html5.section(s,level,contents)
    if Html5.options.containers then
      return format("<section>%s<h%d>%s</h%d>%s%s%s</section>", Html5.containersep, level, s, level, Html5.interblocksep, contents, Html5.containersep)
    else
      return format("<h%d>%s</h%d>%s%s",level,s,level,Html5.interblocksep,contents)
    end
  end

  return Html5
end
