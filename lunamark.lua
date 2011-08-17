#!/usr/bin/env lua

--[[
Copyright (C) 2009-2011 John MacFarlane / Khaled Hosny / Hans Hagen

This is a complete rewrite of the lunamark 0.1 parser.  Hans Hagen
helped a lot to make the parser faster, more robust, and less stack-hungry.
The parser is also more accurate than before.

]]--

local lpeg = require("lpeg")

local myname = ...

local Lunamark = {}

------------------------------------------------------------------------------
-- Utility functions
------------------------------------------------------------------------------

-- from Programming Lua
local function expand_tabs_in_line(s, tabstop)
  local tab = tabstop or 4
  local corr = 0
  return (string.gsub(s, "()\t", function(p)
          local sp = tab - (p - 1 + corr)%tab
          corr = corr - 1 + sp
          return string.rep(" ",sp)
        end))
end

--- return an interator over all lines in a string or file object
function lines(self)
  if type(self) == "file" then
    return io.lines(self)
  else
    if type(self) == "string" then
      local s = self
      if not s:find("\n$") then s = s.."\n" end
      return s:gfind("([^\n]*)\n")
    else
      return io.lines()
    end
  end
end

-- Expands tabs in a string or file object.
-- If no parameter supplied, uses stdin.
local function expand_tabs(inp)
  local buffer = {}
  for line in lines(inp) do
    table.insert(buffer, expand_tabs_in_line(line,4))
  end
  -- need blank line at end to emulate Markdown.pl
  table.insert(buffer, "\n")
  return table.concat(buffer,"\n")
end


function Lunamark.read_markdown(writer, options)

  if not options then options = {} end

  ------------------------------------------------------------------------------

  local lower, upper, gsub, rep, gmatch, format, length =
    string.lower, string.upper, string.gsub, string.rep, string.gmatch,
    string.format, string.len
  local concat = table.concat
  local P, R, S, V, C, Ct, Cg, Cb, Cmt, Cc, Cf, Cs =
    lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Ct, lpeg.Cg, lpeg.Cb,
    lpeg.Cmt, lpeg.Cc, lpeg.Cf, lpeg.Cs
  local lpegmatch = lpeg.match

  ------------------------------------------------------------------------------

  local function if_option(opt)
    return Cmt(P(0), function(s,pos) if options[opt] then return pos else return false end end)
  end

  local function unless_option(opt)
    return Cmt(P(0), function(s,pos) if options[opt] then return false else return pos end end)
  end

  local function diagnostic(x)
    print(format("|%s|",x))
    return x
  end

  ------------------------------------------------------------------------------

  local syntax
  local docsyntax
  local docparser
  local inlinessyntax
  local inlinesparser

  docparser =
    function(str)
      local res = lpegmatch(docsyntax, str)
      if res == nil
        then error(format("docparser failed on:\n%s", str:sub(1,20)))
        else return res
        end
    end

  inlinesparser =
    function(str)
      local res = lpegmatch(inlinessyntax, str)
      if res == nil
        then error(format("inlinesparser failed on:\n%s", str:sub(1,20)))
        else return res
        end
    end

  ------------------------------------------------------------------------------

  local asterisk               = P("*")
  local dash                   = P("-")
  local plus                   = P("+")
  local underscore             = P("_")
  local period                 = P(".")
  local hash                   = P("#")
  local ampersand              = P("&")
  local backtick               = P("`")
  local less                   = P("<")
  local more                   = P(">")
  local space                  = P(" ")
  local squote                 = P("'")
  local dquote                 = P('"')
  local lparent                = P("(")
  local rparent                = P(")")
  local lbracket               = P("[")
  local rbracket               = P("]")
  local slash                  = P("/")
  local equal                  = P("=")
  local colon                  = P(":")
  local semicolon              = P(";")
  local exclamation            = P("!")

  local digit                  = R("09")
  local hexdigit               = R("09","af","AF")
  local letter                 = R("AZ","az")
  local alphanumeric           = R("AZ","az","09")
  local keyword                = letter * alphanumeric^0

  local doubleasterisks        = P("**")
  local doubleunderscores      = P("__")
  local fourspaces             = P("    ")

  local any                    = P(1)
  local always                 = P("")

  local escapable              = S("\\`*_{}[]()+_.!<>#-")
  local anyescaped             = P("\\") / "" * escapable
                               + any

  local tab                    = P("\t")
  local spacechar              = S("\t ")
  local spacing                = S(" \n\r\t")
  local newline                = P("\n")
  local spaceornewline         = spacechar + newline
  local nonspacechar           = any - spaceornewline
  local blocksep               = P("\001")
  local specialchar            = S("*_`*&[]<!\\")
  local normalchar             = any - (specialchar + spaceornewline + blocksep)
  local optionalspace          = spacechar^0
  local spaces                 = spacechar^1
  local eof                    = - any
  local nonindentspace         = space^-3 * - spacechar
  local indent                 = fourspaces + (nonindentspace * tab) / ""
  local linechar               = P(1 - newline)

  local blankline              = optionalspace * newline / "\n"
  local blanklines             = blankline^0
  local skipblanklines         = (optionalspace * newline)^0
  local indentedline           = indent    /"" * C(linechar^1 * (newline + eof))
  local optionallyindentedline = indent^-1 /"" * C(linechar^1 * (newline + eof))
  local spnl                   = optionalspace * (newline * optionalspace)^-1
  local line                   = (any - newline)^0 * newline
                               + (any - newline)^1 * eof
  local nonemptyline           = line - blankline

  ------------------------------------------------------------------------------

  local function lineof(c)
      return (nonindentspace * (P(c) * optionalspace)^3 * newline * blankline^1)
  end

  local lineof_asterisks       = lineof(asterisk)
  local lineof_dashes          = lineof(dash)
  local lineof_underscores     = lineof(underscore)

  -- gobble spaces to make the whole bullet or enumerator four spaces wide:
  local function gobbletofour(s,pos,c)
      if length(c) >= 3
         then return lpegmatch(space^-1,s,pos)
      elseif length(c) == 2
         then return lpegmatch(space^-2,s,pos)
      else return lpegmatch(space^-3,s,pos)
      end
  end

  local bulletchar = plus + asterisk + dash
  local bullet  =  ( bulletchar * #spacing * space^-3
                   + space * bulletchar * #spacing * space^-2
                   + space * space * bulletchar * #spacing * space^-1
                   + space * space * space * bulletchar * #spacing
                   ) * -bulletchar
  local enumerator = digit^3 * period * #spacing
                   + digit^2 * period * #spacing * space^1
                   + digit * period * #spacing * space^-2
                   + space * digit^2 * period * #spacing
                   + space * digit * period * #spacing * space^-1
                   + space * space * digit^1 * period * #spacing

  ------------------------------------------------------------------------------

  local openticks              = Cg(backtick^1, "ticks")
  local closeticks             = space^-1 * Cmt(C(backtick^1) * Cb("ticks"), function(s,i,a,b) return #a == #b and i end)
  local intickschar            = (any - S(" \n\r`"))
                               + (newline * -blankline)
                               + (space - closeticks)
                               + (backtick^1 - closeticks)
  local inticks                = openticks * space^-1 * C(intickschar^1) * closeticks

  ------------------------------------------------------------------------------

  local leader        = space^-3
  local bracketed     = P{ lbracket * ((anyescaped - (lbracket + rbracket)) + V(1))^0 * rbracket }
  local inparens      = P{ lparent * ((anyescaped - (lparent + rparent)) + V(1))^0 * rparent }
  local squoted       = P{ squote * alphanumeric * ((anyescaped-squote) + V(1))^0 * squote }
  local dquoted       = P{ dquote * alphanumeric * ((anyescaped-dquote) + V(1))^0 * dquote }

  local tag           = lbracket * Cs((alphanumeric^1 + bracketed + inticks + (anyescaped-rbracket))^0) * rbracket
  local url           = less * Cs((anyescaped-more)^0) * more
                      + Cs((inparens + (anyescaped-spacing-rparent))^1)
  local title_s       = squote  * Cs(((anyescaped-squote) + squoted)^0) * squote
  local title_d       = dquote  * Cs(((anyescaped-dquote) + dquoted)^0) * dquote
  local title_p       = lparent * Cs((inparens + (anyescaped-rparent))^0) * rparent
  local title         = title_s + title_d + title_p
  local optionaltitle = (spnl^-1 * title * spacechar^0) + Cc("")

  ------------------------------------------------------------------------------
  -- References
  ------------------------------------------------------------------------------

  local references = {}

  local function normalize_tag(tag)
      return lower(gsub(tag, "[ \n\r\t]+", " "))
  end

  local function register_link(tag,url,title)
      references[normalize_tag(tag)] = { url = url, title = title }
  end

  local define_reference_parser = leader * tag * colon * spacechar^0 * url * optionaltitle * blankline^0

  local rparser = (define_reference_parser / register_link + nonemptyline^1 + blankline^1)^0

  local function referenceparser(str)
      lpegmatch(Ct(rparser),str)
  end

  ------

  -- lookup link reference and return either a link or image,
  -- or, if the reference is not found, the original label
  local function indirect_link(img,label,sps,tag)
      local tagpart
      if not tag then
          tag = label
          tagpart = ""
      elseif tag == "" then
          tag = label
          tagpart = "[]"
      else
          tagpart = "[" .. inlinesparser(tag) .. "]"
      end
      if sps then
        tagpart = sps .. tagpart
      end
      local r = references[normalize_tag(tag)]
      if r then
        if img then
          return writer.image(inlinesparser(label), r.url, r.title)
        else
          return writer.link(inlinesparser(label), r.url, r.title)
        end
      else
          return ("[" .. inlinesparser(label) .. "]" .. tagpart)
      end
  end

  local function direct_link(img,label,url,title)
    if img then
      return writer.image(label,url,title)
    else
      return writer.link(label,url,title)
    end
  end

  local image_marker = (exclamation / function() return true end) + Cc(false)

  -- parse a link or image (direct or indirect)
  local link_parser =
        image_marker * (tag / inlinesparser) * spnl^-1 * lparent * (url + Cc("")) * optionaltitle * rparent / direct_link
       + image_marker * tag * (C(spnl^-1) * tag)^-1 / indirect_link

  ------------------------------------------------------------------------------
  -- HTML
  ------------------------------------------------------------------------------

  local blocktags = {
    address = true,
    blockquote = true,
    center = true,
    dir = true,
    div = true,
    p = true,
    pre = true,
    li = true,
    ol = true,
    ul = true,
    dl = true,
    dd = true,
    form = true,
    fieldset = true,
    isindex = true,
    menu = true,
    noframes = true,
    frameset = true,
    h1 = true,
    h2 = true,
    h3 = true,
    h4 = true,
    h5 = true,
    h6 = true,
    hr = true,
    script = true,
    noscript = true,
    table = true,
    tbody = true,
    tfoot = true,
    thead = true,
    th = true,
    td = true,
    tr = true,
  }

  -- make the blocktags table case insensitive
  setmetatable(blocktags, { __index = function(t,k)
      local l = lower(k)
      local v = rawget(t,l) and true or false
      t[k] = v  -- memoize
      return v
  end })

  -- if no argument supplied, matches any keyword
  -- if table supplied, does a table lookup
  -- if string supplied, does a case-insensitive comparison
  local function keyword_matches(f)
    if f then
      return (Cmt(keyword,
        function(s,pos,c)
          local kwmatches
          local typef = type(f)
          if typef == "string" then
            kwmatches = (lower(f) == lower(c))
          elseif typef == "table" then
            kwmatches = f[c]
          else
            error("keyword_matches - unknown type")
          end
          if kwmatches then return pos
          else return false
          end
        end))
    else
      return keyword  -- match any keyword if no argument
    end
  end

  -- There is no reason to support bad html, so we expect quoted attributes
  local htmlattributevalue     = squote * (any - (blankline + squote))^0 * squote
                               + dquote * (any - (blankline + dquote))^0 * dquote

  local htmlattribute          = (alphanumeric + S("_-"))^1 * spnl * equal * spnl * htmlattributevalue * spnl

  local htmlcomment            = P("<!--") * (any - P("-->"))^0 * P("-->")

  local htmlinstruction        = P("<?")   * (any - P("?>" ))^0 * P("?>" )

  local function openelt(f)
    return (less * keyword_matches(f) * spnl * htmlattribute^0 * more)
  end

  local function closeelt(f)
    return (less * slash * keyword_matches(f) * spnl * more)
  end

  local function emptyelt(f)
    return (less * keyword_matches(f) * spnl * htmlattribute^0 * slash * more)
  end

  local displaytext            = (any - less)^1

  local function in_matched(t)
    local p = { openelt(t) * (V(1) + displaytext + (less - closeelt(t)))^0 * closeelt(t) }
    return p
  end

  local displayhtml = htmlcomment + htmlinstruction + emptyelt(blocktags) + openelt("hr") +
                         Cmt(#openelt(blocktags), function(s,pos) local t = lpegmatch(C(less * keyword),s,pos) ; t = t:sub(2); return lpegmatch(in_matched(t),s,pos) end)

  local inlinehtml             = emptyelt() + htmlcomment + htmlinstruction + openelt() + closeelt()

  local hexentity = ampersand * hash * S("Xx") * C(hexdigit    ^1) * semicolon
  local decentity = ampersand * hash           * C(digit       ^1) * semicolon
  local tagentity = ampersand *                  C(alphanumeric^1) * semicolon

  ------------------------------------------------------------------------------

  local Str              = normalchar^1 / writer.string

  local Symbol           = (specialchar - blocksep) / writer.string
  local Code             = inticks      / writer.code

  local HeadingStart     = C(hash * hash^-5) / length
  local HeadingStop      = optionalspace * hash^0 * optionalspace * newline
  local HeadingLevel     = equal^1 * Cc(1)
                         + dash ^1 * Cc(2)

  local Endline          = newline * -(
                               blankline
                             + blocksep
                             + eof
                             + more
                             + HeadingStart
                             + ( line * (P("===")^3 + P("---")^3) * newline )
                           ) / writer.space

  local Space            = spacechar / "" *
                         ( spacechar^1 * Endline / writer.linebreak
                         + spacechar^0 * Endline^-1 * eof / ""
                         + spacechar^0 * Endline^-1 * optionalspace / writer.space
                         )

  local function between(p, starter, ender)
      local ender2 = lpeg.B(nonspacechar) * ender
      return (starter * #nonspacechar * Cs(p * (p - ender2)^0) * ender2)
  end

  local Strong = ( between(V("Inline"), doubleasterisks, doubleasterisks)
                 + between(V("Inline"), doubleunderscores, doubleunderscores) ) / writer.strong

  local Emph   = ( between(V("Inline"), asterisk, asterisk)
                 + between(V("Inline"), underscore, underscore)) / writer.emphasis

  local AutoLinkUrl      = less * C(alphanumeric^1 * P("://") * (anyescaped - (newline + more))^1)       * more / writer.url_link

  local AutoLinkEmail    = less * C((alphanumeric + S("-._+"))^1 * P("@") * (anyescaped - (newline + more))^1) * more / writer.email_link

  local Link             = link_parser  -- includes images

  local UlOrStarLine     = asterisk^4
                         + underscore^4
                         + (spaces * S("*_")^1 * #spaces) / writer.string

  local EscapedChar      = S("\\") * C(escapable) / writer.string

  local InlineHtml       = C(inlinehtml)  / writer.inline_html
  local DisplayHtml      = C(displayhtml) / writer.display_html
  local HtmlEntity       = hexentity / writer.hex_entity
                         + decentity / writer.dec_entity
                         + tagentity / writer.tag_entity

  local Verbatim         = Cs((blanklines * (indentedline - blankline)^1)^1)  / writer.verbatim

  local Blockquote       = Cs((
                              ((nonindentspace * more * space^-1)/"" * linechar^0 * newline)^1
                            * ((linechar - blankline)^1 * newline)^0
                            * blankline^0
                           )^1) / docparser / writer.blockquote

  local HorizontalRule   = (lineof_asterisks + lineof_dashes + lineof_underscores) / writer.hrule

  local Reference        = define_reference_parser / ""

  local Paragraph        = nonindentspace * Cs(V("Inline")^1) * newline * blankline^1 / writer.paragraph

  ------------------------------------------------------------------------------
  -- Lists
  ------------------------------------------------------------------------------

  local NestedList            = Cs((optionallyindentedline - (bullet + enumerator))^1) / function(a) return "\001"..a end
  local ListBlockLine         = -blankline * -(indent^-1 * (bullet + enumerator)) * optionallyindentedline
  local ListBlock             = line * ListBlockLine^0
  local ListContinuationBlock = blanklines * (indent / "") * ListBlock

  local function TightListItem(starter)
      return (starter * Cs(ListBlock * NestedList^-1) * -(blanklines * indent) / docparser / writer.listitem)
  end

  local function LooseListItem(starter)
      return (starter * Cs(ListBlock * Cc("\n") * (NestedList + ListContinuationBlock^0) * (blanklines / "\n\n")) / docparser / writer.listitem)
  end

  local BulletList =
               Cs(TightListItem(bullet)^1)  * Cc(true) * skipblanklines * -bullet    / writer.bulletlist
             + Cs(LooseListItem(bullet)^1)  * Cc(false) * skipblanklines             / writer.bulletlist

  local OrderedList =
               Cs(TightListItem(enumerator)^1) * Cc(true) * skipblanklines * -enumerator  / writer.orderedlist
              + Cs(LooseListItem(enumerator)^1) * Cc(false) * skipblanklines         / writer.orderedlist

  ------------------------------------------------------------------------------
  -- Headers
  ------------------------------------------------------------------------------

  local AtxHeader = HeadingStart * optionalspace * Cs((V("Inline") - HeadingStop)^1) * HeadingStop / writer.heading
  local SetextHeader = #(line * S("=-")) * Cs(line / inlinesparser)
                         * HeadingLevel *  optionalspace * newline / function(a,b) return writer.heading(b,a) end

  ------------------------------------------------------------------------------
  -- Syntax specification
  ------------------------------------------------------------------------------

  function syntax(start)
    return { start,

      Document              = V("Block")^0,

      Inlines               = V("Inline")^0,

      Block                 = blankline^1 / ""
                            + blocksep / "\n"
                            + Blockquote
                            + Verbatim
                            + HorizontalRule
                            + BulletList
                            + OrderedList
                            + AtxHeader
                            + DisplayHtml
                            + SetextHeader
                            + Reference
                            + Paragraph
                            + Cs(V("Inline")^1),

      Inline                = Str
                            + Space
                            + Endline
                            + UlOrStarLine
                            + Strong
                            + Emph
                            + Link
                            + Code
                            + AutoLinkUrl
                            + AutoLinkEmail
                            + InlineHtml
                            + HtmlEntity
                            + EscapedChar
                            + Symbol,
    }
  end

  docsyntax = Cs(syntax("Document"))
  inlinessyntax = Cs(syntax("Inlines"))

  ------------------------------------------------------------------------------
  -- Conversion function
  ------------------------------------------------------------------------------

  -- inp can be a string or a file object.
  local function convert(inp)
      references = {}
      local expanded = expand_tabs(inp)
      referenceparser(expanded)
      local result = writer.start_document() .. docparser(expanded) .. writer.stop_document()
      return result
  end

  return convert

end

local write_html = require("writer.html")
Lunamark.writers = { html = write_html }

------------------------------------------------------------------------------
-- Main program - act as module if 'required', else as program.
------------------------------------------------------------------------------

-- http://lua-users.org/lists/lua-l/2007-02/msg00125.html
if type(package.loaded[myname]) == "userdata" then
    return Lunamark  -- put module stuff here
  else
    local cmdopts = require("cmdopts")
    local args = cmdopts.getargs(
       "lunamark [options] [file..] - convert text from markdown",
       { to = {shortform = true, arg = "format", description = "Target format"},
       })
    local writer
    if not args.t or args.t == "html" then
      writer = Lunamark.writers.html
    else
      print("Unknown writer: " .. args.t)
      os.exit(3)
    end
    writer.options.minimize = false
    writer.options.blanklines = false
    io.input(args.input)
    -- local prof = require("profiler")
    -- prof.start()
    io.write(Lunamark.read_markdown(writer,{})(io.stdin))
    -- io.write(Lunamark.read_markdown(writer,{})("hi\n\nthere"))
    -- prof.stop()
  end

