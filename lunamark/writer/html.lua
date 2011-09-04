-- (c) 2009-2011 John MacFarlane. Released under MIT license.
-- See the file LICENSE in the source for details.

local M = {}

local xml = require("lunamark.writer.xml")
local util = require("lunamark.util")
local format = string.format
local gsub = string.gsub

function M.new(options)
  local Html = xml.new(options)

  local endnotes = {}

  Html.linebreak = "<br/>"

  function Html.code(s)
    return format("<code>%s</code>",Html.string(s))
  end

  function Html.link(lab,src,tit)
    local titattr
    if type(tit) == "string" and #tit > 0
       then titattr = format(" title=\"%s\"", Html.string(tit))
       else titattr = ""
       end
    return format("<a href=\"%s\"%s>%s</a>",Html.string(src),titattr,lab)
  end

  function Html.image(lab,src,tit)
    local titattr, altattr
    if type(tit) == "string" and #tit > 0
       then titattr = format(" title=\"%s\"", Html.string(tit))
       else titattr = ""
       end
    return format("<img src=\"%s\" alt=\"%s\"%s />",Html.string(src),Html.string(lab),titattr)
  end

  function Html.paragraph(s)
    return format("<p>%s</p>",s)
  end

  local function listitem(s)
    return format("<li>%s</li>", s)
  end

  function Html.bulletlist(items,tight)
    local buffer = {}
    for _,item in ipairs(items) do
      buffer[#buffer + 1] = listitem(item)
    end
    local contents = table.concat(buffer,Html.containersep)
    return format("<ul>%s%s%s</ul>",Html.containersep,contents,Html.containersep)
  end

  function Html.orderedlist(items,tight,startnum)
    local start = ""
    if startnum and startnum ~= 1 then
      start = format(" start=\"%d\"",startnum)
    end
    local buffer = {}
    for _,item in ipairs(items) do
      buffer[#buffer + 1] = listitem(item)
    end
    local contents = table.concat(buffer,Html.containersep)
    return format("<ol%s>%s%s%s</ol>",start,Html.containersep,contents,Html.containersep)
  end

  function Html.inline_html(s)
    return s
  end

  function Html.display_html(s)
    return format("%s",s)
  end

  function Html.emphasis(s)
    return format("<em>%s</em>",s)
  end

  function Html.strong(s)
    return format("<strong>%s</strong>",s)
  end

  function Html.blockquote(s)
    return format("<blockquote>%s%s%s</blockquote>",
                 Html.containersep, s, Html.containersep)
  end

  function Html.verbatim(s)
    return format("<pre><code>%s</code></pre>", Html.string(s))
  end

  function Html.section(s,level,contents)
    if options.containers then
      return format("<div>%s<h%d>%s</h%d>%s%s%s</div>", Html.containersep,
           level, s, level, Html.interblocksep, contents, Html.containersep)
    else
      return format("<h%d>%s</h%d>%s%s",level,s,level,Html.interblocksep,contents)
    end
  end

  Html.hrule = "<hr />"

  function Html.note(contents)
    local num = #endnotes + 1
    local backref = format(' <a href="#fnref%d" class="footnoteBackLink">↩</a>', num)
    local adjusted = gsub(contents, "()</p>$", backref)
    endnotes[num] = format('<li id="fn%d">%s</li>', num, adjusted)
    return format('<sup><a href="#fn%d" class="footnoteRef" id="fnref%d">%d</a></sup>',num,num,num)
  end

  function Html.stop_document()
    return format('%s<ol class="notes">%s%s%s</ol>', Html.interblocksep, Html.containersep,
       table.concat(endnotes, Html.interblocksep), Html.containersep)
  end

  return Html
end

return M
