----------------------------------------------------
-- world_miniwindow module
-- adapted from aard_layout by Fiendish and Lasher
----------------------------------------------------

--[[

Mods: Ruthgul, for Materia Magica

2014-07-23
* moved all miniwindow related code into this module, for easier maintenance
* renamed the background and logo images to bg.png and mm_logo.png, which must be located in MUSHclient/worlds (in case someone wants to use them, they need to be RGB, 8 bits per channel)
* replaced the resizer code with the one from generic_miniwindow.lua for a more consistent look (code by Lasher, Enelya)

--]]


-- Defaults

default_top = 7
default_bottom = 544
default_left = 7
default_right = 650

black = GetNormalColour(1)
darkergray = 0x333333


-- Variables not saved.
startx      = ""
starty      = ""
posx        = ""
posy        = ""
hotspot_id  = ""
orig_height = 400 -- saves old height when we collapse window.
MIN_SIZE    = 50
rstagsize   = 15



--=================================================================================
-- Called when plugin is first installed, including when Mush first starts.
-- This is the place to initialize stuff you need in the main plugin.
--=================================================================================

function do_Install()
  -- Get a unique name for main window and resizer window.
  win = GetPluginID() -- get a unique name
  textDragger = "      " .. win .. "txtdragger"
  textResizer = "      " .. win .. "txtresize"
  bgwin = "      " .. win .. "text_background"
  bgoffscreen = "      " .. win .. "text_background_offscreen"

  local mushdir = GetInfo(66)
  local imgpath = mushdir .. "worlds\\mm_bg.png"
  SetBackgroundImage(imgpath, miniwin.pos_tile)
--  if 0 ~= SetBackgroundImage(imgpath, miniwin.pos_tile) then
--    ColourNote("yellow","red","Error loading background image.")
--  end

  WindowCreate(bgwin, 0, 0, 0, 0,
               miniwin.pos_center_all,
               miniwin.create_underneath + miniwin.create_absolute_location,
               black)
  WindowCreate(bgoffscreen, 0, 0, 0, 0,
               miniwin.pos_center_all,
               miniwin.create_underneath + miniwin.create_absolute_location,
               black)

  local logopath = mushdir .. "worlds\\mm_logo.png"
  if WindowLoadImage(bgoffscreen, "mm_logo", logopath) == 0 then
    local img_width = WindowImageInfo(bgoffscreen, "mm_logo", 2)
    local img_height = WindowImageInfo(bgoffscreen, "mm_logo", 3)

    WindowResize(bgoffscreen, img_width, img_height, black)
    WindowDrawImage(bgoffscreen, "mm_logo", 0, 0, 0, 0, miniwin.image_copy)
    WindowFilter(bgoffscreen, 0, 0, 0, 0,
                 miniwin.filter_red_brightness,
                 bit.band(black, 0xFF))
    WindowFilter(bgoffscreen, 0, 0, 0, 0,
                 miniwin.filter_green_brightness,
                 bit.band(bit.shr(black, 8), 0xFF))
    WindowFilter(bgoffscreen, 0, 0, 0, 0,
                 miniwin.filter_blue_brightness,
                 bit.band(bit.shr(black, 16), 0xFF))
    WindowImageFromWindow(bgwin, "mm_logo", bgoffscreen)

    img_width = WindowImageInfo(bgwin, "mm_logo", 2)
    img_height = WindowImageInfo(bgwin, "mm_logo", 3)
    image_ratio = img_width / img_height
  end

  -- Pull some state variables.
  check_main_background()

  -- give main world window time to stabilize its size and position
  AddTimer("checkTimer", 0, 0, 2, "",
           timer_flag.Enabled + timer_flag.OneShot + timer_flag.ActiveWhenClosed + timer_flag.Replace + timer_flag.Temporary,
           "check_main_background")

  -- if disabled last time, stay disabled
  if GetVariable("enabled") == "false" then
    ColourNote("yellow", "", "Warning: Plugin " .. GetPluginName() .. " is currently disabled.")
    check(EnablePlugin(GetPluginID(), false))
    return
  end -- they didn't enable us last time
end


function check_main_background()
  local output_width = GetInfo(281)
  local output_height = GetInfo(280)

  textrect_top = math.max(0, tonumber(GetVariable("trtop")) or default_top)
  textrect_bottom = math.min(output_height, tonumber(GetVariable("trbottom")) or default_bottom)
  textrect_left = math.max(0, tonumber(GetVariable("trleft")) or default_left)
  textrect_right = math.min(output_width, tonumber(GetVariable("trright")) or default_right)
  draw_main_window()
end


function add_main_resizer()
  local tr_right = GetInfo(274)
  local tr_bottom = GetInfo(275)

  local x1 = tr_right - rstagsize + 7
  local y1 = tr_bottom - rstagsize + 7
  local size = rstagsize

  if WindowInfo(textResizer, 1) then -- if it already exists
    -- Reposition the resize tag.
    WindowPosition(textResizer, x1, y1,
                   miniwin.pos_stretch_to_view,
                   miniwin.create_absolute_location + miniwin.create_transparent)

  else
    -- Add another mini-window in bottom right corner for resizer tag.
    check(WindowCreate(textResizer, x1, y1, size, size,
                       miniwin.pos_center_all,
                       miniwin.create_absolute_location,
                       black))

    -- draw the resize widget bottom right corner.
    local HIGHLIGHT = ColourNameToRGB("silver")
    local SHADOW = ColourNameToRGB("gray")
    x1 = 0
    y1 = 0
    local x2 = x1 + size
    local y2 = y1 + size

    local m = 0 -- 2
    local n = 0 -- 2
    while (x1 + m + 2 <= x2 - 3 and y1 + n + 1 <= y2 - 4) do
      WindowLine(textResizer, x1 + m + 1, y2 - 4, x2 - 3, y1 + n,
                 HIGHLIGHT,
                 miniwin.pen_solid,
                 1)
      WindowLine(textResizer, x1 + m + 2, y2 - 4, x2 - 3, y1 + n + 1,
                 SHADOW,
                 miniwin.pen_solid,
                 1)
      m = m + 3
      n = n + 3
    end

    -- Add a drag handler to this window, effectively allows textrectangle to be resized.
    WindowAddHotspot(textResizer, "resizemain", 0, 0, 0, 0,
                     "MouseOver", "CancelMouseOver",
                     "MouseDown", "CancelMouseDown",
                     "MouseUp", "",
                     miniwin.cursor_nw_se_arrow,
                     0)
    WindowDragHandler(textResizer,
                      "resizemain",
                      "ResizeMainCallback", "ResizeReleaseMainCallback",
                      0)
  end

  WindowShow(textResizer, true)
end


function add_title_dragger()
  local tr_left = GetInfo(272)
  local tr_top = GetInfo(273)
  local tr_right = GetInfo(274)

  if WindowInfo(textDragger, 1) then -- if it already exists
    --- Reposition the dragger tag.
    WindowPosition(textDragger, tr_left - 6, tr_top - 7,
                   miniwin.pos_stretch_to_view,
                   miniwin.create_absolute_location + miniwin.create_transparent)

  else
    -- Add another mini-window at top for dragging bar.
    dragsize = 10

    check(WindowCreate(textDragger, tr_left - 6, tr_top - 6, tr_right - tr_left + 11, dragsize,
                       miniwin.pos_center_all,
                       miniwin.create_absolute_location,
                       black))

    WindowAddHotspot(textDragger, "dragmain", 0, 0, 0, 0,
                     "MouseOver", "CancelMouseOver",
                     "MouseDown", "CancelMouseDown",
                     "MouseUp", "Drag to move window",
                     miniwin.cursor_both_arrow,
                     0)
    WindowDragHandler(textDragger,
                      "dragmain",
                      "DragMainCallback", "DragReleaseMainCallback",
                      0)
  end

  WindowShow(textDragger, true)
end


function OnPluginWorldOutputResized()
  AddTimer("checkTimer", 0, 0, .1, "",
           timer_flag.Enabled + timer_flag.OneShot + timer_flag.ActiveWhenClosed + timer_flag.Replace + timer_flag.Temporary,
           "check_main_background")
end


function draw_main_window()
  local output_width = GetInfo(281)
  local output_height = GetInfo(280)

  -- addresses a problem where new users are trying to play without the window maximized
  local t_right = math.min(textrect_right, output_width - 7)
  local t_bottom = math.min(textrect_bottom, output_height - 7)

  TextRectangle(textrect_left, textrect_top, t_right, t_bottom,
                5, -- BorderOffset,
                ColourNameToRGB("darkgray"), -- BorderColour,
                2, -- BorderWidth,
                darkergray, -- OutsideFillColour,
                miniwin.brush_solid) -- OutsideFillStyle

  -- Add a mini-window under main text area so background won't mess it up.
  local trwidth = t_right - textrect_left
  local trheight = t_bottom - textrect_top

  WindowCreate(bgwin, textrect_left - 5, textrect_top - 5,
               math.max(0, trwidth + 10), math.max(0, trheight + 10),
               miniwin.pos_center_all,
               miniwin.create_underneath + miniwin.create_absolute_location,
               black)
  WindowShow(bgwin, true)

  if image_ratio ~= nil then
    local rect_ratio = trwidth / trheight
    if rect_ratio > image_ratio then
      image_height = trheight
      image_width = trheight * image_ratio
    else
      image_height = trwidth / image_ratio
      image_width = trwidth
    end

    WindowDrawImage(bgwin, "mm_logo",
                    (trwidth - image_width) / 2,
                    (trheight - image_height) / 2,
                    (trwidth + image_width) / 2,
                    (trheight + image_height) / 2,
                    miniwin.image_stretch)
  end

  add_title_dragger()
  add_main_resizer()
end


function ResizeMainCallback()
  local output_width = GetInfo(281)
  local output_height = GetInfo(280)

  posx, posy = WindowInfo(textResizer, 17), WindowInfo(textResizer, 18)
  textrect_right = textrect_right + posx - startx
  startx = posx

  if (textrect_right - textrect_left < MIN_SIZE) then
    textrect_right = textrect_left + MIN_SIZE
    startx = textrect_right
  elseif (textrect_right > output_width - 7) then
    textrect_right = output_width - 7
    startx = textrect_right
  end

  textrect_bottom = textrect_bottom + posy - starty
  starty = posy

  if (textrect_bottom - textrect_top < MIN_SIZE) then
    textrect_bottom = textrect_top + MIN_SIZE
    starty = textrect_bottom
  elseif (textrect_bottom > output_height - 7) then
    textrect_bottom = output_height - 7
    starty = textrect_bottom
  end

  draw_main_window()
end


function DragMainCallback()
  local output_width = GetInfo(281)
  local output_height = GetInfo(280)

  local act_tr_left = GetInfo(290)
  local act_tr_right = GetInfo(292)
  local act_tr_top = GetInfo(291)
  local act_tr_bottom = GetInfo(293)

  posx, posy = WindowInfo(textDragger, 17), WindowInfo(textDragger, 18)
  local height = act_tr_bottom - act_tr_top
  local width = act_tr_right - act_tr_left

  textrect_left = textrect_left + posx - startx
  textrect_right = textrect_left + width

  if (textrect_left <= 7) then
    textrect_left = 7
    textrect_right = textrect_left + width
  elseif (textrect_right >= output_width - 7) then
    textrect_right = output_width - 7
    textrect_left = textrect_right - width
  else
    startx = posx
  end

  textrect_top = textrect_top + posy - starty
  textrect_bottom = textrect_top + height
  starty = posy

  if (textrect_top < 7) then
    textrect_top = 7
    starty = textrect_top
    textrect_bottom = textrect_top + height
  elseif (textrect_bottom > output_height - 7) then
    textrect_bottom = output_height - 7
    textrect_top = textrect_bottom - height
    starty = textrect_top
  end

  draw_main_window()
end



---------------------------------------------------------------------------------
-- Called after the resize widget is released.
---------------------------------------------------------------------------------

function ResizeReleaseMainCallback()
  do_SaveState()
end


function DragReleaseMainCallback()
  do_SaveState()
end



---------------------------------------------------------------------------------
-- Called when mouse button is pressed on hotspot.
---------------------------------------------------------------------------------

function MouseDown(flags, hotspot_id)
  if (hotspot_id == "resizemain") then
    startx, starty = WindowInfo(textResizer, 17), WindowInfo(textResizer, 18)
  elseif (hotspot_id == "dragmain") then
    startx, starty = WindowInfo(textDragger, 17), WindowInfo(textDragger, 18)
  end
end



---------------------------------------------------------------------------------
-- Called when mouse moved away from hotspot. Doesn't really apply for draggables.
---------------------------------------------------------------------------------

function CancelMouseDown(flags, hotspot_id)
end



---------------------------------------------------------------------------------
-- Called when mouse button released on hotspot.
---------------------------------------------------------------------------------

function MouseUp(flags, hotspot_id)
end



---------------------------------------------------------------------------------
-- Called when plugin is saved - store our variables for next time.
---------------------------------------------------------------------------------

function do_SaveState()
  local is_enabled = GetPluginInfo(GetPluginID(), 17)
  SetVariable("enabled", tostring(is_enabled))

  SetVariable("trleft",textrect_left)
  SetVariable("trright",textrect_right)
  SetVariable("trtop",textrect_top)
  SetVariable("trbottom",textrect_bottom)
end


function do_reset_mini()
  textrect_left = default_left
  textrect_right = default_right
  textrect_top = default_top
  textrect_bottom = default_bottom

  do_SaveState()
  check_main_background()
end


function do_Close()
  do_Disable()
  WindowDelete(textDragger)
  WindowDelete(textResizer)
  WindowDelete(bgwin)
end


function do_Disable()
  do_SaveState()

  TextRectangle(0, 0, 0, 0,
                5, -- BorderOffset,
                ColourNameToRGB("darkgray"), -- BorderColour,
                2, -- BorderWidth,
                ColourNameToRGB("darkslategray"), -- OutsideFillColour,
                miniwin.brush_solid) -- OutsideFillStyle (fine hatch)

  SetBackgroundImage("", 0)
  WindowShow(textDragger, false)
  WindowShow(textResizer, false)
  WindowShow(bgwin, false)
end
