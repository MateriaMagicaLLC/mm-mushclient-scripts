------------------------------------------------------------
-- generic_miniwindow module
-- adapted from Chat_Capture_Miniwindow by Enelya,
-- in turn adapted from aard_channels_fiendish by Fiendish
------------------------------------------------------------

--[[

Mods: Ruthgul, for Materia Magica

2017-02-18
* made restore_defaults() auto-reposition the miniwindow to top-left

2015-03-14
* fixed an issue that happened when ResizeMoveCallback() was called before startx, starty were initialized

2014-11-01
* (hopefully) fixed a wrap text issue that affected windows with scrollbars

2014-08-16
* added copy selected text to clipboard (adapted from aard_channels_fiendish)

2014-07-30
* added support for scroll-wheel

2014-07-25
* fixed resize so it won't allow to make the mini larger than the containing world window

2014-07-23
* added a parameter to do_install_miniwindow, to allow the creation of miniwindows without scrollbars
* fixed the math to show the miniwindow title centered
* made it load saved values for BODY_FONT_NAME and BODY_FONT_SIZE (they were saved but not loaded on reinstall)

2013-04-20
* moved all miniwindow related code into this module, for easier maintenance and reusability

--]]


require "movewindow" -- load the movewindow.lua module
require "copytable"
require "wait"

initialized = false

BODY_FONT_NAME = GetVariable("bodyfont") or "Lucida Console"
BODY_FONT_SIZE = GetVariable("font_size") or 9

SCROLL_BAR_WIDTH = 15
MAX_LINES = 10000 -- how many lines to store in scrollback

default_WIDTH = 100
default_HEIGHT = 50

WINDOW_WIDTH = tonumber(GetVariable("WINDOW_WIDTH") or default_WIDTH)
WINDOW_HEIGHT = tonumber(GetVariable("WINDOW_HEIGHT") or default_HEIGHT)

-- offset of text from edge
TEXT_INSET = 3

-- where to store the captured line
lines = {} -- table of recent captured lines
rawlines = {}

lineStart = 0
lineEnd = 0
WINDOW_COLUMNS = 0
WINDOW_LINES = 0

wheel_lines = 3

theme = {
  WINDOW_BACKGROUND = ColourNameToRGB("black"), -- for miniwindow body
  WINDOW_BORDER = ColourNameToRGB("silver"), -- for miniwindow body

  HIGHLIGHT = ColourNameToRGB("silver"), -- for 3D surfaces
  FACE = ColourNameToRGB("black"), -- for 3D surfaces
  INNERSHADOW = ColourNameToRGB("gray"), -- for 3D surfaces
  OUTERSHADOW = ColourNameToRGB("gray"), -- for 3D surfaces

  BACK_FACE = ColourNameToRGB("black"), -- for contrasting details
  DETAIL = ColourNameToRGB("silver"), -- for contrasting details

  SELECT_FILL = ColourNameToRGB("dimgray"),

  TITLE_HEIGHT = 17, -- for miniwindow title area
  TITLE_FONT_NAME = "Lucida Console", -- for miniwindow title area
  TITLE_FONT_SIZE = 9 -- for miniwindow title area
} -- end theme table


-- replacement for WindowRectOp action 5, which allows for a 3D look while maintaining color theme
-- Requires global theme.HIGHLIGHT, theme.FACE, theme.INNERSHADOW, and theme.OUTERSHADOW rgb colors to be set.

function DrawThemed3DRect(Window, left, top, right, bottom, visible)
  if (visible == nil) then
    visible = true
  end

  WindowRectOp(Window, miniwin.rect_fill, left, top, right, bottom, theme.FACE)

  if (visible) then
    WindowLine(Window, left, top, right, top, theme.HIGHLIGHT,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
    WindowLine(Window, left, top, left, bottom, theme.HIGHLIGHT,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
    WindowLine(Window, left, bottom - 2, right, bottom - 2, theme.INNERSHADOW,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
    WindowLine(Window, right - 2, top, right - 2, bottom - 2, theme.INNERSHADOW,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
    WindowLine(Window, left, bottom - 1, right, bottom - 1, theme.OUTERSHADOW,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
    WindowLine(Window, right - 1, top, right - 1, bottom - 1, theme.OUTERSHADOW,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)

  else
    WindowLine(Window, left, bottom - 1, right, bottom - 1, theme.HIGHLIGHT,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
    WindowLine(Window, right - 1, top, right - 1, bottom - 1, theme.HIGHLIGHT,
               miniwin.pen_solid + miniwin.pen_endcap_flat, 1)
  end
end -- function DrawThemed3DRect


function DrawThemedResizeTag(Window, x1, y1, size)
  local x2, y2 = x1 + size, y1 + size
  DrawThemed3DRect(Window, x1, y1, x2, y2, draw_scrollbars)

  local m = 2
  local n = 2

  if (not draw_scrollbars) then
    x1 = x1 + 1
    y1 = y1 + 1
    x2 = x2 + 1
    y2 = y2 + 1
  end

  while (x1 + m + 2 <= x2 - 3 and y1 + n + 1 <= y2 - 4) do
    WindowLine(Window, x1 + m + 1, y2 - 4, x2 - 3, y1 + n, theme.HIGHLIGHT, miniwin.pen_solid, 1)
    WindowLine(Window, x1 + m + 2, y2 - 4, x2 - 3, y1 + n + 1, theme.INNERSHADOW, miniwin.pen_solid, 1)
    m = m + 3
    n = n + 3
  end
end -- function DrawThemedResizeTag


Win = GetPluginID()
font_height = nil
line_height = nil
windowinfo = ""
startx = nil
starty = nil


last_refresh = 0

function ResizeMoveCallback()
  posx, posy = WindowInfo(Win, 17), WindowInfo(Win, 18)

  local output_width = GetInfo(281)
  local output_height = GetInfo(280)

  WINDOW_WIDTH = WINDOW_WIDTH + posx - (startx or 0)
  startx = posx

  -- auto-fix window width
  if (WindowTextWidth(Win, title_font, WINDOW_TITLE) + 2 * scroll_width > WINDOW_WIDTH) then
    WINDOW_WIDTH = WindowTextWidth(Win, title_font, WINDOW_TITLE) + 2 * scroll_width
    startx = windowinfo.window_left + WINDOW_WIDTH
  elseif (windowinfo.window_left + WINDOW_WIDTH > output_width) then
    WINDOW_WIDTH = output_width - windowinfo.window_left
    startx = output_width
  end

  WINDOW_HEIGHT = WINDOW_HEIGHT + posy - (starty or 0)
  starty = posy

  -- auto-fix window height
  if (3 * scroll_width + 10 + line_height + theme.TITLE_HEIGHT > WINDOW_HEIGHT) then
    WINDOW_HEIGHT = 3 * SCROLL_BAR_WIDTH + 10 + line_height + theme.TITLE_HEIGHT
    starty = windowinfo.window_top + WINDOW_HEIGHT

  elseif (windowinfo.window_top + WINDOW_HEIGHT > output_height) then
    WINDOW_HEIGHT = output_height - windowinfo.window_top
    starty = output_height
  end

  if (utils.timer() - last_refresh > 0.0333) then
    init(false)
    last_refresh = utils.timer()
  end
end -- function ResizeMoveCallback


function ResizeReleaseCallback()
  WINDOW_HEIGHT = theme.TITLE_HEIGHT + (line_height * (WINDOW_LINES - 1)) + 3
  init(true)
end -- ResizeReleaseCallback


function do_install_miniwindow(title, show_it, has_scrollbars)
  draw_scrollbars = has_scrollbars
  if (draw_scrollbars == nil) then
    draw_scrollbars = true -- for compatibility
  end

  if (draw_scrollbars) then
    scroll_width = SCROLL_BAR_WIDTH
  else
    scroll_width = 0
  end

  title_font = "titlefont" .. Win
  body_font = "bodyfont" .. Win

  WINDOW_TITLE = title
  WINDOW_VISIBLE = show_it

  -- Dummy window to get font characteristics
  check(WindowCreate(Win, 0, 0, 1, 1, 0, 0, theme.WINDOW_BACKGROUND))
  check(WindowFont(Win, body_font, BODY_FONT_NAME, BODY_FONT_SIZE))
  check(WindowFont(Win, title_font, theme.TITLE_FONT_NAME, theme.TITLE_FONT_SIZE))
  font_height = WindowFontInfo(Win, body_font, 1) - WindowFontInfo(Win, body_font, 4) + 1
  line_height = font_height + 1
  font_width = WindowTextWidth(Win, body_font, "W")

  -- install the window movement handler, get back the window position
  windowinfo = movewindow.install(Win, miniwin.pos_top_right, miniwin.create_absolute_location, true)

  init(true)

  if (show_it) then
    mini_show()
  end
end -- function do_install_miniwindow


function init(firstTime)
  -- how many lines and columns will fit?
  WINDOW_LINES = math.ceil((WINDOW_HEIGHT - theme.TITLE_HEIGHT) / line_height)
  WINDOW_COLUMNS = math.ceil((WINDOW_WIDTH - scroll_width) / font_width)

  if firstTime then
    WindowCreate(Win, windowinfo.window_left, windowinfo.window_top, WINDOW_WIDTH, WINDOW_HEIGHT, windowinfo.window_mode, windowinfo.window_flags, theme.WINDOW_BACKGROUND)

    -- catch for right-click menu and line selection
    WindowAddHotspot(Win, "textarea", 0, theme.TITLE_HEIGHT, WINDOW_WIDTH - scroll_width,0, "", "", "MouseDown", "CancelMouseDown", "MouseUp", "", miniwin.cursor_ibeam, 0)
    WindowDragHandler(Win, "textarea", "TextareaMoveCallback", "TextareaReleaseCallback", 0x10)

    -- add the drag handler so they can move the window around
    movewindow.add_drag_handler(Win, 0, 0, 0, theme.TITLE_HEIGHT, miniwin.cursor_both_arrow)

    if (draw_scrollbars) then
      -- scroll bar up/down buttons
      WindowAddHotspot(Win, "up", WINDOW_WIDTH - scroll_width, theme.TITLE_HEIGHT, 0, theme.TITLE_HEIGHT + scroll_width, "MouseOver", "CancelMouseOver", "MouseDown", "CancelMouseDown", "MouseUp", "", miniwin.cursor_hand, 0)

      WindowAddHotspot(Win, "down", WINDOW_WIDTH - scroll_width, WINDOW_HEIGHT - (2 * scroll_width), 0, WINDOW_HEIGHT - scroll_width, "MouseOver", "CancelMouseOver", "MouseDown", "CancelMouseDown", "MouseUp", "", miniwin.cursor_hand, 0)

      -- support for scroll-wheel to the text area
      WindowScrollwheelHandler(Win, "textarea", "WheelMoveCallback")
    end

    -- add the resize widget hotspot
    WindowAddHotspot(Win, "resizer", WINDOW_WIDTH - SCROLL_BAR_WIDTH, WINDOW_HEIGHT - SCROLL_BAR_WIDTH, WINDOW_WIDTH, WINDOW_HEIGHT, "MouseOver", "CancelMouseOver", "MouseDown", "CancelMouseDown", "MouseUp", "", miniwin.cursor_nw_se_arrow, 0)

    WindowDragHandler(Win, "resizer", "ResizeMoveCallback", "ResizeReleaseCallback", 0)

  else
    WindowResize(Win, WINDOW_WIDTH, WINDOW_HEIGHT, theme.WINDOW_BACKGROUND)

    WindowMoveHotspot(Win, "textarea", 0, theme.TITLE_HEIGHT, WINDOW_WIDTH - scroll_width, 0)

    if (draw_scrollbars) then
      WindowMoveHotspot(Win, "up", WINDOW_WIDTH - scroll_width, theme.TITLE_HEIGHT, 0, theme.TITLE_HEIGHT + scroll_width)

      WindowMoveHotspot(Win, "down", WINDOW_WIDTH - scroll_width, WINDOW_HEIGHT - (2 * scroll_width), 0, WINDOW_HEIGHT - scroll_width)
    end

    WindowMoveHotspot(Win, "resizer", WINDOW_WIDTH - scroll_width, WINDOW_HEIGHT - scroll_width, WINDOW_WIDTH, 0)
  end -- if

  WindowShow(Win, true)

  if (firstTime) then
    lines = {}
    for _, styles in ipairs(rawlines) do
      fillBuffer(styles)
    end -- for each line
  end -- if

  lineStart = math.max(1, #lines - WINDOW_LINES + 2)
  lineEnd = math.max(1, #lines)
  refresh()

  if (not WINDOW_VISIBLE) then
    mini_hide()
  end

  initialized = true
end -- function init


function save_status()
  movewindow.save_state(Win)
  SetVariable("WINDOW_WIDTH", WINDOW_WIDTH)
  SetVariable("WINDOW_HEIGHT", WINDOW_HEIGHT)
end -- function save_status


-- display one line
function Display_Line(line, styles, backfill_start, backfill_end)
  local left = TEXT_INSET
  local top = theme.TITLE_HEIGHT + (line * line_height) + 1
  local bottom = top + line_height

  if (styles) then
    if (backfill_start) and (backfill_end) then
      WindowRectOp(Win, miniwin.rect_fill, backfill_start, top - 1, backfill_end, bottom - 1, theme.SELECT_FILL)
    end -- backfill

    for _, style in ipairs(styles) do
      local width = WindowTextWidth(Win, body_font, style.text) -- get width of text
      local right = left + width

      if (style.backcolour ~= theme.WINDOW_BACKGROUND) then -- draw background
        if ((not backfill_start) and (not backfill_end))
        or (backfill_end < left)
        or (backfill_start > right) then
          WindowRectOp(Win, miniwin.rect_fill, left, top - 1, right, bottom - 1, style.backcolour)

        elseif (backfill_start) and (backfill_end) then
          if (backfill_start > left) then
            WindowRectOp(Win, miniwin.rect_fill, left, top - 1, backfill_start, bottom - 1, style.backcolour)
          end

          if (backfill_end < right) then
            WindowRectOp(Win, miniwin.rect_fill, backfill_end, top - 1, right, bottom - 1, style.backcolour)
          end
        end
      end

      local t = style.text
      -- clean up dangling newlines that cause block characters to show
      if string.sub(style.text, -1) == "\n" then
        t = string.sub(style.text, 1, -2)
      end

      WindowText(Win, body_font, t, left, top, 0, 0, style.textcolour) -- draw text
      left = left + width -- advance horizontally
    end -- for each style run
  end -- if  styles
end -- Display_Line


-- display all visible lines
function writeLines()
  local ax = nil
  local zx = nil
  local line_no_colors = ""

  if #lines >= 1 then
    for count = lineStart, lineEnd do
      ax = nil
      zx = nil
      line_no_colors = strip_colors(lines[count][1])

      -- create highlighting parameters when text is selected
      if copy_start_line ~= nil and copy_end_line ~= nil
      and count >= copy_start_line and count <= copy_end_line then
        ax = (((count == copy_start_line) and math.min(start_copying_x, WindowTextWidth(Win, body_font, line_no_colors) + TEXT_INSET)) or TEXT_INSET)

        -- end of highlight for this line
        zx = math.min(WINDOW_WIDTH - scroll_width, (((count == copy_end_line) and math.min(end_copying_x, WindowTextWidth(Win, body_font, line_no_colors) + TEXT_INSET)) or WindowTextWidth(Win, body_font, line_no_colors) + TEXT_INSET))
      end

      Display_Line(count - lineStart, lines[count][1], ax, zx)
    end -- for each line
    Redraw()
  end
end -- function writeLines


function strip_colors(styles, startcol, endcol)
  local startcol = startcol or 1
  local endcol = endcol or 99999 -- 99999 is assumed to be long enough to cover ANY style run

  local copystring = ""

  -- skip unused style runs at the start
  local style_start = 0
  local first_style = 0
  local last_style = 0

  for num, style in ipairs(styles) do
    if startcol <= style_start + style.length then
      first_style = num
      startcol = startcol - style_start
      break
    end

    style_start = style_start + style.length
  end

  -- startcol larger than the sum length of all styles? return empty string
  if first_style == 0 then
    return copystring
  end

  for i = first_style, #styles do
    local style = styles[i]
    local text = string.sub(style.text, startcol, endcol - style_start)

    copystring = copystring .. text

    -- stopping here before the end?
    if endcol <= style_start + style.length then
      break
    end

    -- all styles after the first one have startcol of 1
    startcol = 1
    style_start = style_start + style.length
  end

  return copystring
end -- function strip_colors


-- clear and redraw
function refresh()
  WindowRectOp(Win, miniwin.rect_fill, 0, 0, WINDOW_WIDTH, WINDOW_HEIGHT, theme.WINDOW_BACKGROUND)
  drawStuff()
end -- function refresh


barPos = ""
barSize = ""
totalSteps = ""


function drawStuff()
  wait.make(function()
    while (not initialized) do
      wait.time(.5)
    end

    -- draw border
    WindowRectOp(Win, miniwin.rect_frame, 0, 0, 0, 0, theme.WINDOW_BORDER)

    -- Title bar
    DrawThemed3DRect(Win, 0, 0, WINDOW_WIDTH, theme.TITLE_HEIGHT)

    -- Title text
    local title_width = WindowTextWidth(Win, "titlefont" .. Win, WINDOW_TITLE)

    WindowText(Win, "titlefont" .. Win, WINDOW_TITLE, (WINDOW_WIDTH - title_width - scroll_width) / 2, (theme.TITLE_HEIGHT - line_height) / 2, WINDOW_WIDTH, theme.TITLE_HEIGHT, theme.DETAIL, false)

    if #lines >= 1 then
      writeLines()
    end -- if

    -- Scrollbar base
    if (draw_scrollbars) then
      WindowRectOp(Win, miniwin.rect_fill, WINDOW_WIDTH - scroll_width, theme.TITLE_HEIGHT, WINDOW_WIDTH, WINDOW_HEIGHT, theme.BACK_FACE) -- scroll bar background

      WindowRectOp(Win, miniwin.rect_frame, WINDOW_WIDTH - scroll_width + 1, scroll_width + theme.TITLE_HEIGHT + 1, WINDOW_WIDTH - 1, WINDOW_HEIGHT - (2 * scroll_width) - 1, theme.DETAIL) -- scroll bar background inset rectangle

      DrawThemed3DRect(Win, WINDOW_WIDTH - scroll_width, theme.TITLE_HEIGHT, WINDOW_WIDTH, theme.TITLE_HEIGHT + scroll_width) -- top scroll button

      DrawThemed3DRect(Win, WINDOW_WIDTH - scroll_width, WINDOW_HEIGHT - (scroll_width * 2), WINDOW_WIDTH, WINDOW_HEIGHT - scroll_width) -- bottom scroll button

      -- draw triangle in up button
      points = string.format("%i,%i,%i,%i,%i,%i",
               (WINDOW_WIDTH - scroll_width) + 2,
               theme.TITLE_HEIGHT + 8,
               (WINDOW_WIDTH - scroll_width) + 6,
               theme.TITLE_HEIGHT + 4,
               (WINDOW_WIDTH - scroll_width) + 10,
               theme.TITLE_HEIGHT + 8)

      WindowPolygon(Win, points, theme.DETAIL,
                    miniwin.pen_solid, 1, -- pen (solid, width 1)
                    theme.DETAIL,
                    miniwin.brush_solid, --brush (solid)
                    true, --close
                    false) --alt fill

      -- draw triangle in down button
      points = string.format("%i,%i,%i,%i,%i,%i",
               (WINDOW_WIDTH - scroll_width) + 2,
               (WINDOW_HEIGHT - scroll_width) - 10,
               (WINDOW_WIDTH - scroll_width) + 6,
               (WINDOW_HEIGHT - scroll_width) - 6,
               (WINDOW_WIDTH - scroll_width) + 10,
               (WINDOW_HEIGHT - scroll_width) - 10)

      WindowPolygon(Win, points, theme.DETAIL,
                    miniwin.pen_solid, 1, -- pen (solid, width 1)
                    theme.DETAIL,
                    miniwin.brush_solid, --brush (solid)
                    true, --close
                    false) --alt fill

      -- The scrollbar position indicator
      totalSteps = #lines

      if (totalSteps <= WINDOW_LINES - 1) then
        totalSteps = 1
      end

      SCROLL_BAR_HEIGHT = (WINDOW_HEIGHT - (3 * scroll_width) - theme.TITLE_HEIGHT)

      if (not dragscrolling) then
        stepNum = lineStart - 1

        barPos = scroll_width + theme.TITLE_HEIGHT + ((SCROLL_BAR_HEIGHT / totalSteps) * stepNum)

        barSize = (SCROLL_BAR_HEIGHT / math.max(WINDOW_LINES - 1, totalSteps)) * (WINDOW_LINES - 1)

        if barSize < 10 then
          barSize = 10
        end

        if barPos+barSize > scroll_width + theme.TITLE_HEIGHT + SCROLL_BAR_HEIGHT then
          barPos = scroll_width + theme.TITLE_HEIGHT + SCROLL_BAR_HEIGHT - barSize
        end

        WindowAddHotspot(Win, "scroller", (WINDOW_WIDTH - scroll_width), barPos, WINDOW_WIDTH, barPos + barSize, "MouseOver", "CancelMouseOver", "MouseDown", "CancelMouseDown", "MouseUp", "", miniwin.cursor_hand, 0)

        WindowDragHandler(Win, "scroller", "ScrollerMoveCallback", "ScrollerReleaseCallback", 0)
      end -- if

      DrawThemed3DRect(Win, WINDOW_WIDTH - scroll_width, barPos, WINDOW_WIDTH, barPos + barSize)
    end

    -- resizer tag
    DrawThemedResizeTag(Win, WINDOW_WIDTH - SCROLL_BAR_WIDTH, WINDOW_HEIGHT - SCROLL_BAR_WIDTH, SCROLL_BAR_WIDTH)

    Redraw()
  end)
end -- function drawStuff


function ScrollerMoveCallback(flags, hotspot_id)
  mouseposy = WindowInfo(Win, 18)
  windowtop = WindowInfo(Win, 2)
  barPos = math.max(mouseposy - windowtop + clickdelta, scroll_width + theme.TITLE_HEIGHT)

  if barPos > WINDOW_HEIGHT - (scroll_width * 2) - barSize then
    barPos = WINDOW_HEIGHT - (scroll_width * 2) - barSize
    lineStart = math.max(1, #lines - WINDOW_LINES + 2)
    lineEnd = #lines

  else
    lineStart = math.floor((barPos - scroll_width - theme.TITLE_HEIGHT) / (SCROLL_BAR_HEIGHT / totalSteps) + 1)

    lineEnd = math.min(lineStart + WINDOW_LINES - 2, #lines)
  end -- if

  refresh()
end -- function ScrollerMoveCallback


function ScrollerReleaseCallback(flags, hotspot_id)
  dragscrolling = false
  refresh()
end -- function ScrollerReleaseCallback


function fillBuffer(rawstyles)
  local avail = 0
  local line_styles
  local beginning = true

  -- keep pulling out styles and trying to fit them on the current line
  local styles = copytable.deep(rawstyles)
  local remove = table.remove
  local insert = table.insert

  while #styles > 0 do
    if avail <= 0 then -- no room available? start new line
      -- remove first line if filled up
      if #lines >= MAX_LINES then
        remove(lines, 1)
      end -- if

      avail = WINDOW_WIDTH - scroll_width - (TEXT_INSET * 2) -- - 4
      line_styles = {}
      add_line(line_styles, beginning)
      beginning = false
    end -- line full

    -- get next style, work out how long it is
    local style = remove(styles, 1)
    local width = WindowTextWidth(Win, body_font, style.text)

    -- if it fits, copy whole style in
    if width <= avail then
      insert(line_styles, style)
      avail = avail - width

    else -- otherwise, have to split style
      -- look for trailing space (work backwards). remember where space is
      local col = style.length - 1
      local split_col

      -- keep going until out of columns
      while col > 1 do
        width = WindowTextWidth(Win, body_font, style.text:sub(1, col))

        if width <= avail then
          if not split_col then
            split_col = col -- in case no space found, this is where we can split
          end -- if

          -- see if space here
          if style.text:sub(col, col) == " " then
            split_col = col
            break
          end -- if space
        end -- if will now fit
        col = col - 1
      end -- while

      -- if we found a place to split, use old style, and make it shorter. Also make a copy and put the rest in that
      if split_col then
        insert(line_styles, style)
        local style_copy = copytable.shallow(style)
        style.text = style.text:sub(1, split_col)
        style.length = split_col
        style_copy.text = style_copy.text:sub(split_col + 1)
        style_copy.length = #style_copy.text
        insert(styles, 1, style_copy)

      elseif next(line_styles) == nil then
        insert(line_styles, style)

      else
        insert(styles, 1, style)
      end -- if

      avail = 0 -- now we need to wrap
    end -- if could not fit whole thing in
  end -- while we still have styles over
end -- function fillBuffer


-- Main capture routine
function log_to_mini(name, line, wildcards, styles)
  if (initialized) then
    -- store the raw lines for use during resizing
    if #rawlines >= MAX_LINES then
      table.remove(rawlines, 1)
    end
    table.insert(rawlines, styles)

    fillBuffer(styles)
    refresh()
  end
end -- function log_to_mini


function add_line(line, is_beginning_of_message)
  -- add new line
  table.insert(lines, {line, false})
  lines[#lines][2] = is_beginning_of_message

  -- advance the count
  if #lines >= WINDOW_LINES then
    lineStart = lineStart + 1
  end -- if

  if #lines > 1 then
    lineEnd = lineEnd + 1
  end -- if
end -- function add_line


keepscrolling = false


function scrollbar(calledBy)
  wait.make(function()
    while (keepscrolling) do
      if calledBy == "up" then
        if (lineStart > 1) then
          lineStart = lineStart - 1
          lineEnd = lineEnd - 1

          WindowRectOp(Win, miniwin.rect_draw_edge, (WINDOW_WIDTH - scroll_width), theme.TITLE_HEIGHT, 0, theme.TITLE_HEIGHT + scroll_width, miniwin.rect_edge_sunken,  miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle) -- up arrow pushed

          points = string.format ("%i,%i,%i,%i,%i,%i",
                   (WINDOW_WIDTH - scroll_width) + 3,
                   theme.TITLE_HEIGHT + 9,
                   (WINDOW_WIDTH - scroll_width) + 7,
                   theme.TITLE_HEIGHT + 5,
                   (WINDOW_WIDTH - scroll_width) + 11,
                   theme.TITLE_HEIGHT + 9)

          WindowPolygon(Win, points, theme.DETAIL,
                        miniwin.pen_solid, 1, -- pen (solid, width 1)
                        theme.DETAIL,
                        miniwin.brush_solid, -- brush (solid)
                        true, -- close
                        false) -- alt fill

        else
          keepscrolling = false
        end

      elseif calledBy == "down" then
        if (lineEnd < #lines) then
          lineStart = lineStart + 1
          lineEnd = lineEnd + 1

          WindowRectOp(Win, miniwin.rect_draw_edge, (WINDOW_WIDTH - scroll_width), WINDOW_HEIGHT - (scroll_width * 2), 0, WINDOW_HEIGHT - scroll_width - 1, miniwin.rect_edge_sunken,  miniwin.rect_edge_at_all + miniwin.rect_option_fill_middle) -- down arrow pushed

          points = string.format ("%i,%i,%i,%i,%i,%i",
                   (WINDOW_WIDTH - scroll_width) + 3,
                   (WINDOW_HEIGHT - scroll_width) - 11,
                   (WINDOW_WIDTH - scroll_width) + 7,
                   (WINDOW_HEIGHT - scroll_width) - 7,
                   (WINDOW_WIDTH - scroll_width) + 11,
                   (WINDOW_HEIGHT - scroll_width) - 11) -- draw triangle in up button

          WindowPolygon(Win, points, theme.DETAIL,
                        miniwin.pen_solid, 1, -- pen (solid, width 1)
                        theme.DETAIL,
                        miniwin.brush_solid, -- brush (solid)
                        true, -- close
                        false) -- alt fill

        else
          keepscrolling = false
        end
      end -- if

      wait.time(0.1)
      refresh()
    end -- while keepscrolling
  end) -- wait.make
end -- function scrollbar


function MouseOver(flags, hotspot_id)
  keepscrolling = false
end -- function MouseOver


function CancelMouseOver(flags, hotspot_id)
  keepscrolling = false
end -- function CancelMouseOver


function MouseDown(flags, hotspot_id)
  if (hotspot_id == "resizer") then
    startx, starty = WindowInfo(Win, 17), WindowInfo(Win, 18)

  elseif (hotspot_id == "scroller") then
    clickdelta = WindowHotspotInfo(Win, "scroller", 2) - WindowInfo(Win, 15)
    dragscrolling = true

  elseif (hotspot_id == "up" or hotspot_id == "down") then
    keepscrolling = true
    scrollbar(hotspot_id)

  elseif (hotspot_id == "textarea" and flags == miniwin.hotspot_got_lh_mouse) then
    temp_start_copying_x = WindowInfo(Win, 14)
    start_copying_y = WindowInfo(Win, 15)
    copy_start_windowline = math.floor((start_copying_y - theme.TITLE_HEIGHT) / line_height)
    temp_start_line = copy_start_windowline + lineStart
    copied_text = ""
    copy_start_line = nil
    copy_end_line = nil
    writeLines()
  end -- if
end -- function MouseDown


function CancelMouseDown(flags, hotspot_id)
  keepscrolling = false
  refresh()
end -- function CancelMouseDown


function MouseUp(flags, hotspot_id)
  if (hotspot_id == "textarea" and flags == miniwin.hotspot_got_rh_mouse) then
    -- build menu for current state
    right_click_menu()

  else
    refresh()
  end

  keepscrolling = false
end -- function MouseUp


function WheelMoveCallback(flags, hotspot_id)
  keepscrolling = true

  if bit.band(flags, miniwin.wheel_scroll_back) ~= 0 then
    -- wheel scrolled down (towards you)
    for i = 1, wheel_lines do
      scrollbar("down")
    end
  else
    -- wheel scrolled up (away from you)
    for i = 1, wheel_lines do
      scrollbar("up")
    end
  end -- if

  keepscrolling = false
end -- function WheelMoveCallback


end_copying_x = 0
end_copying_y = 0

function TextareaMoveCallback(flags, hotspot_id)
  if bit.band(flags, miniwin.hotspot_got_lh_mouse) ~= 0 then -- only on left mouse button
    copied_text = ""
    end_copying_x = WindowInfo(Win, 17) - WindowInfo(Win, 1)
    end_copying_y = WindowInfo(Win, 18) - WindowInfo(Win, 2)
    local ypos = end_copying_y
    end_copying_x = math.max(TEXT_INSET, math.min(end_copying_x, WINDOW_WIDTH - scroll_width))
    end_copying_y = math.max(theme.TITLE_HEIGHT + 1, math.min(end_copying_y, theme.TITLE_HEIGHT - 1 + (line_height * (WINDOW_LINES - 1))))
    copy_end_windowline = math.floor((end_copying_y - theme.TITLE_HEIGHT) / line_height)
    copy_end_line = copy_end_windowline + lineStart
    copy_start_line = temp_start_line
    start_copying_x = temp_start_copying_x

    if not copy_start_line then
      -- OS bug causing errors for me. hack around stupid mouse click tracking mess
      return
    end

    if (copy_start_line > #lines) then
      start_copying_x = WINDOW_WIDTH - scroll_width
    end

    -- the user is selecting backwards, so reverse the start/end orders
    if copy_end_line < temp_start_line then
      copy_start_line, copy_end_line = copy_end_line, copy_start_line
      start_copying_x, end_copying_x = end_copying_x, start_copying_x
    end -- if

    if copy_end_line == copy_start_line and end_copying_x < start_copying_x then
      start_copying_x, end_copying_x = end_copying_x, start_copying_x
    end -- if

    for copy_line = copy_start_line, copy_end_line do
      if (lines[copy_line] ~= nil) then
        local startpos = 1
        local endpos = 99999

        if (copy_line - lineStart + 1 > 0
        and copy_line - lineStart < WINDOW_LINES
        and copy_line - lineStart < #lines) then
          -- snap to character boundaries instead of selecting arbitrary pixel widths
          local line_no_colors = strip_colors(lines[copy_line][1])
          startpos = 1
          endpos = #line_no_colors

          -- special deal for the first line
          if copy_line == copy_start_line then
            for pos = 1, #line_no_colors do
              startpos = pos
              if WindowTextWidth(Win, body_font, string.sub(line_no_colors, 1, pos)) > start_copying_x then
                start_copying_x = WindowTextWidth(Win, body_font, string.sub(line_no_colors, 1, pos - 1)) + TEXT_INSET
                break
              end
            end
          end

          -- special deal for the last line
          if copy_line == copy_end_line then
            local found = false
            endpos = 0

            for pos = 1, #line_no_colors do
              if WindowTextWidth(Win, body_font, string.sub(line_no_colors, 1, pos)) > end_copying_x then
                end_copying_x = WindowTextWidth(Win, body_font, string.sub(line_no_colors, 1, endpos)) + TEXT_INSET
                found = true
                break
              end

              endpos = pos
            end
          end
        end -- if should show highlight

        -- store selected area for later
        copied_part = strip_colors(lines[copy_line][1], startpos, endpos)

        if copy_line ~= copy_end_line
        and copy_line ~= #lines
        and lines[copy_line+1][2] == true then
          -- only put a line break if the next line is from a different message
          copied_part = copied_part .. "\n"
        end

        copied_text = copied_text .. (((copied_part ~= nil) and copied_part) or "")
      end -- if valid line
    end -- for

    if ypos < theme.TITLE_HEIGHT then
      keepscrolling = true
      scrollbar("up")

    elseif ypos > WINDOW_HEIGHT then
      keepscrolling = true
      scrollbar("down")

    else
      keepscrolling = false
      writeLines()
    end
  end -- if left mouse button
end -- function TextareaMoveCallback


function TextareaReleaseCallback(flags, hotspot_id)
  copy_start_line = math.min(#lines, copy_start_line or 0)
  copy_end_line = math.min(#lines, copy_end_line or 0)
end -- function TextareaReleaseCallback


function mini_show()
  WindowShow(Win, true)
  WINDOW_VISIBLE = true
end -- function mini_show


function mini_hide()
  WindowShow(Win, false)
  WINDOW_VISIBLE = false
end -- function mini_hide


function clear_mini()
  lines = {} -- table of recent captured lines
  rawlines = {}
  lineStart = math.max(1, #lines - WINDOW_LINES + 2)
  lineEnd = math.max(1, #lines)

  refresh()
end -- function clear_mini


-- right click menu
function right_click_menu()
  menustring = "copy selection to clipboard|copy all to clipboard|change font"

  result = WindowMenu(Win,
                      WindowInfo(Win, 14), -- x position
                      WindowInfo(Win, 15), -- y position
                      menustring)          -- content

  if result == "copy selection to clipboard" then
    CopySelectedText()
    Note("-- " .. GetPluginInfo(GetPluginID(), 1) .. ": selected text copied to clipboard --")

  elseif result == "copy all to clipboard" then
    GetAllBufferedMessages()
    Note("-- " .. GetPluginInfo(GetPluginID(), 1) .. ": all buffered messages copied to clipboard --")

  elseif result == "change font" then
    wanted_font = utils.fontpicker(BODY_FONT_NAME, BODY_FONT_SIZE) -- font dialog

    if wanted_font then
      BODY_FONT_NAME = wanted_font.name
      BODY_FONT_SIZE = wanted_font.size
      SetVariable("bodyfont", BODY_FONT_NAME)
      SetVariable("font_size", BODY_FONT_SIZE)
      do_install_miniwindow(WINDOW_TITLE, WINDOW_VISIBLE, draw_scrollbars)
    end
  end -- if
end -- function right_click_menu


function CopySelectedText()
  SetClipboard(copied_text)
end -- function CopySelectedText


function GetAllBufferedMessages()
  local t = {}

  for _, styles in ipairs(rawlines) do
    table.insert(t, GetLineText(styles))
  end -- for

  SetClipboard(table.concat(t,"\r\n"))
end -- function GetAllBufferedMessages


function GetLineText(styles)
  local t = {}

  for _, style in ipairs(styles) do
    table.insert(t, style.text)
  end -- for

  return table.concat(t)
end -- function GetLineText


function restore_defaults()
  WINDOW_WIDTH = default_WIDTH
  WINDOW_HEIGHT = default_HEIGHT
  WindowPosition(Win, 0, 0, 0, miniwin.create_absolute_location)

  ResizeMoveCallback()
end -- function restore_defaults
