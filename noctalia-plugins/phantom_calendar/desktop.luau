--!nonstrict
-- Persona 5 Royal field calendar HUD, drawn from the game's own sprites. Those come from the user's own
-- copy of the game via tools/extract-game-assets.sh and are never shipped with this plugin.
-- Every sprite is a white alpha mask that gets tinted per layer (like the game does); the HUD is composed
-- as SVG, rendered to PNG with rsvg-convert, and the weather icon animates by cycling frames.

local REFRESH_SECONDS = 15 * 60
local SETUP_RETRY_SECONDS = 60
-- composition space = pixels of the 1920x1080 in-game screenshot the layout was traced from
local SVG_W, SVG_H = 460, 330
local SHOW_W, SHOW_H = 490, 352
local RENDER_W = 1104
local WEATHER_FRAMES = 3
local DEFAULT_ASSETS = "~/.local/share/p5-game-assets/dump/P5_FIELD_DAY"
local COLOR_FILE = "~/.cache/noctalia/phantom-calendar-color.txt"
local GAME_RED = "#e6191e"
local DARK = "#1a0d0a"

-- sprite ids in P5_FIELD_DAY.SPD
local WEATHER_CARD = 96
local WEATHER_ICONS = { [0] = { 97, 109, 110 }, [1] = { 98, 111, 112 }, [2] = { 99, 113, 114 }, [3] = { 100, 115, 116 } }
-- weekday and time of day sprites are in these orders
local WEEKDAY = { Sun = 0, Mon = 1, Tue = 2, Wed = 3, Thu = 4, Fri = 5, Sat = 6 }
local TIME_OF_DAY = { EARLY_MORNING = 0, MORNING = 1, DAYTIME = 2, LUNCHTIME = 3, AFTERNOON = 4, AFTER_SCHOOL = 5, EVENING = 6, LATE_NIGHT = 7 }

-- { cx, cy, scale, rotation } per element, matched against an in-game screenshot
local LAYOUT = {
  month = { 95, 92, 0.45, -6 },
  tens = { 188, 88, 0.42, -4 },
  ones = { 266, 82, 0.42, -3 },
  single = { 227, 85, 0.42, -3 },
  weather = { 365, 62, 0.42, 10 },
  weekday = { 279, 155, 0.47, -26 },
  timeOfDay = { 102, 259, 0.43, -24 },
}

noctalia.setUpdateInterval(1000)

-- the built-in sysmon widgets use Anton, so keep it registered
local antonFamily, antonErr = noctalia.loadFont("assets/Anton-Regular.ttf")
if not antonFamily then
  noctalia.log(`phantom_calendar: couldn't load Anton ({antonErr})`)
end

local dataDir, dataErr = noctalia.pluginDataDir()
local imgDir = dataDir and `{dataDir}/img`
local hasRsvg = noctalia.commandExists("rsvg-convert")

local ready, settingUp, lastSetupTry = false, false, nil
local sizes = {}
local status = nil

local weather = nil
local coords, coordsFor = nil, nil
local lastFetch = nil

local wallpaperColor, colorMtime = nil, nil

local frames, frameIndex = {}, 1
local shownKey = nil
local rendering, pending = false, false

local function now()
  return tonumber(noctalia.formatTime("%s")) or 0
end

local function sh(s)
  return "'" .. (string.gsub(s, "'", "'\\''")) .. "'"
end

local function shellSetting(path)
  local ok, value = pcall(noctalia.getSetting, path)
  if ok then
    return value
  end
  return nil
end

local function assetsDir()
  local own = noctalia.string.trim(noctalia.getConfig("game_assets_dir") or "")
  return noctalia.expandPath(if own ~= "" then own else DEFAULT_ASSETS)
end

local function currentAddress()
  local own = noctalia.string.trim(noctalia.getConfig("address") or "")
  if own ~= "" then
    return own
  end
  local shell = shellSetting("location.address")
  if type(shell) == "string" then
    return noctalia.string.trim(shell)
  end
  return ""
end

-- P5 has no school on weekends, so the daytime slots collapse into "Daytime"
local function timeOfDay(hour, weekend)
  if hour < 5 then
    return TIME_OF_DAY.LATE_NIGHT
  elseif hour < 8 then
    return TIME_OF_DAY.EARLY_MORNING
  elseif weekend and hour < 18 then
    return TIME_OF_DAY.DAYTIME
  elseif hour < 12 then
    return TIME_OF_DAY.MORNING
  elseif hour < 13 then
    return TIME_OF_DAY.LUNCHTIME
  elseif hour < 15 then
    return TIME_OF_DAY.AFTERNOON
  elseif hour < 18 then
    return TIME_OF_DAY.AFTER_SCHOOL
  elseif hour < 22 then
    return TIME_OF_DAY.EVENING
  end
  return TIME_OF_DAY.LATE_NIGHT
end

-- P5 only has sunny, rain, cloudy and snow; open-meteo codes: https://open-meteo.com/en/docs
local function conditionFor(code)
  if code <= 1 then
    return 0
  elseif (code >= 71 and code <= 77) or code == 85 or code == 86 then
    return 3
  elseif code >= 51 then
    return 1
  end
  return 2
end

local function refreshWallpaperColor()
  local info = noctalia.fileInfo(COLOR_FILE)
  local mtime = if info then info.mtime else 0
  if mtime == colorMtime then
    return
  end
  colorMtime = mtime
  local text = noctalia.readFile(COLOR_FILE)
  wallpaperColor = if text then string.match(text, "#%x%x%x%x%x%x") else nil
end

local function weekdayColor()
  if noctalia.getConfig("weekday_color") == "wallpaper" and wallpaperColor then
    return wallpaperColor
  end
  return GAME_RED
end

-- ── svg ──────────────────────────────────────────────────────────────────────

local function tintFilter(id, color)
  return string.format(
    '<filter id="%s" color-interpolation-filters="sRGB"><feFlood flood-color="%s"/><feComposite in2="SourceAlpha" operator="in"/></filter>',
    id, color
  )
end

-- one sprite centered on the element's layout point; filter = tint id, or nil to keep it white
local function sprite(id, layout, filter)
  local size = sizes[id]
  if not size then
    return ""
  end
  return string.format(
    '<g transform="translate(%g %g) rotate(%g) scale(%g)"><image x="%g" y="%g" width="%d" height="%d" href="img/spr_%03d.png"%s/></g>',
    layout[1], layout[2], layout[4], layout[3], -size.w / 2, -size.h / 2, size.w, size.h, id,
    if filter then ` filter="url(#{filter})"` else ""
  )
end

local function elements(s, frame)
  -- layers of one element share its center; false = nothing on that pass
  local list = {
    { layout = LAYOUT.month, layers = { { s.month }, { 12 + s.month, "black" }, { 24 + s.month } } },
  }
  local function digit(d, layout)
    table.insert(list, { layout = layout, layers = { { 37 + d }, { 47 + d, "black" }, { 57 + d } } })
  end
  if s.day >= 10 then
    digit(math.floor(s.day / 10), LAYOUT.tens)
    digit(s.day % 10, LAYOUT.ones)
  else
    digit(s.day, LAYOUT.single)
  end
  if s.weather then
    local icon = WEATHER_ICONS[s.weather.condition][frame + 1]
    table.insert(list, { layout = LAYOUT.weather, layers = { { WEATHER_CARD }, false, { icon, "black" } } })
  end
  local w = s.weekday
  table.insert(list, { layout = LAYOUT.weekday, layers = { { 67 + w }, { 74 + w, "black" }, { 81 + w, "accent" }, { 287 + w, "black" } } })
  local t = s.timeOfDay
  table.insert(list, { layout = LAYOUT.timeOfDay, layers = { { 88 + t }, { 125 + t, "dark" } } })
  return list
end

local function buildSvg(s, frame)
  local out = {
    string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', SVG_W, SVG_H, SVG_W, SVG_H),
    "<defs>" .. tintFilter("black", "#000") .. tintFilter("dark", DARK) .. tintFilter("accent", s.accent) .. "</defs>",
  }
  -- every element's white base first, then every black base, then the tops, so the white bases
  -- merge into one sticker the way they do in game
  local list = elements(s, frame)
  for pass = 1, 4 do
    for _, element in list do
      local layer = element.layers[pass]
      if layer then
        table.insert(out, sprite(layer[1], element.layout, layer[2]))
      end
    end
  end
  table.insert(out, "</svg>")
  return table.concat(out, "\n")
end

-- ── rendering ────────────────────────────────────────────────────────────────

local function currentState()
  local weekday = WEEKDAY[noctalia.formatTime("%a")] or 0
  return {
    month = tonumber(noctalia.formatTime("%m")) or 1,
    day = tonumber(noctalia.formatTime("%d")) or 1,
    weekday = weekday,
    timeOfDay = timeOfDay(tonumber(noctalia.formatTime("%H")) or 0, weekday == 0 or weekday == 6),
    weather = weather,
    accent = weekdayColor(),
  }
end

local function contentKey(s)
  return table.concat({
    s.month, s.day, s.weekday, s.timeOfDay, s.accent,
    if s.weather then s.weather.condition else "",
  }, "|")
end

local function show()
  if #frames > 0 then
    desktopWidget.render(ui.image({ path = frames[frameIndex], width = SHOW_W, height = SHOW_H, fit = "contain" }))
  elseif status then
    desktopWidget.render(ui.label({ text = status, color = "#ffffff", maxWidth = SHOW_W }))
  else
    desktopWidget.render(ui.column({}, {}))
  end
end

local function redraw()
  if not ready then
    return
  end
  if rendering then
    pending = true
    return
  end

  local s = currentState()
  local key = contentKey(s)
  if key == shownKey then
    return
  end

  rendering = true
  local stamp = noctalia.nowMs()
  local count = if s.weather then WEATHER_FRAMES else 1
  local rendered = {}

  local function finish(ok)
    rendering = false
    if ok then
      local old = frames
      frames, shownKey, frameIndex = rendered, key, 1
      show()
      for _, path in old do
        noctalia.removeFile(path)
      end
    else
      for _, path in rendered do
        noctalia.removeFile(path)
      end
    end
    if pending then
      pending = false
      redraw()
    end
  end

  local function renderFrame(i)
    if i > count then
      finish(true)
      return
    end
    local svgPath = `{dataDir}/hud-{i}.svg`
    -- new name every render, so an image can't be served from a stale cache
    local pngPath = `{dataDir}/hud-{stamp}-{i}.png`
    local ok, err = noctalia.writeFile(svgPath, buildSvg(s, i - 1))
    if not ok then
      noctalia.log(`phantom_calendar: couldn't write svg ({err})`)
      finish(false)
      return
    end
    noctalia.runAsync(`rsvg-convert -w {RENDER_W} {sh(svgPath)} -o {sh(pngPath)}`, function(res)
      if res.exitCode ~= 0 then
        noctalia.log(`phantom_calendar: rsvg-convert failed ({res.exitCode})`)
        finish(false)
        return
      end
      table.insert(rendered, pngPath)
      renderFrame(i + 1)
    end, 15000)
  end

  renderFrame(1)
end

-- ── setup ────────────────────────────────────────────────────────────────────

local function setStatus(text)
  status = text
  show()
end

local function setup()
  lastSetupTry = now()
  if not hasRsvg then
    setStatus(noctalia.tr("status.no_rsvg"))
    return
  end
  if not dataDir then
    noctalia.log(`phantom_calendar: no plugin data dir ({dataErr})`)
    return
  end

  local root = assetsDir()
  local text = noctalia.readFile(`{root}/index.json`)
  local index = if text then noctalia.json.decode(text) else nil
  if type(index) ~= "table" or type(index.sprites) ~= "table" then
    setStatus(`{noctalia.tr("status.missing_assets")} {root}`)
    return
  end
  sizes = {}
  for _, entry in index.sprites do
    if not entry.skipped and entry.w > 0 and entry.h > 0 then
      sizes[entry.id] = { w = entry.w, h = entry.h }
    end
  end

  -- rsvg-convert refuses images outside the svg's own directory (symlinks included), so copy them in
  local cmd = `mkdir -p {sh(imgDir)} && cp -f {sh(root)}/spr_*.png {sh(imgDir)}/`
  settingUp = true
  noctalia.runAsync(cmd, function(res)
    settingUp = false
    if res.exitCode ~= 0 then
      noctalia.log(`phantom_calendar: copying sprites failed ({res.exitCode})`)
      setStatus(`{noctalia.tr("status.missing_assets")} {root}`)
      return
    end
    status = nil
    ready = true
    redraw()
  end, 30000)
end

-- ── weather ──────────────────────────────────────────────────────────────────

-- weather is optional: on failure just drop it and log why
local function fail(detail)
  weather = nil
  noctalia.log(`phantom_calendar: {detail}`)
  redraw()
end

local function fetchCurrent()
  local url = "https://api.open-meteo.com/v1/forecast"
    .. `?latitude={coords.lat}&longitude={coords.lon}`
    .. "&current=weather_code"

  noctalia.http({ url = url }, function(res)
    if not res.ok or res.status >= 400 then
      fail(`forecast request failed ({res.status})`)
      return
    end
    local data = noctalia.json.decode(res.body)
    if type(data) ~= "table" or type(data.current) ~= "table" then
      fail("unexpected forecast response")
      return
    end
    weather = { condition = conditionFor(data.current.weather_code) }
    redraw()
  end)
end

local function geocode(address)
  -- open-meteo searches by place name, so match the country/region part ourselves
  local name, rest = string.match(address, "^([^,]+),?%s*(.*)$")
  name = noctalia.string.trim(name or address)
  rest = string.lower(noctalia.string.trim(rest or ""))
  local url = `https://geocoding-api.open-meteo.com/v1/search?count=10&language=en&format=json&name={noctalia.string.urlEncode(name)}`

  noctalia.http({ url = url }, function(res)
    if not res.ok or res.status >= 400 then
      fail(`geocoding request failed ({res.status})`)
      return
    end
    local data = noctalia.json.decode(res.body)
    local results = type(data) == "table" and data.results or nil
    if type(results) ~= "table" or #results == 0 then
      fail("no geocoding results")
      return
    end

    local pick = results[1]
    if rest ~= "" then
      for _, r in results do
        local country = string.lower(r.country or "")
        local region = string.lower(r.admin1 or "")
        if string.find(country, rest, 1, true) or string.find(region, rest, 1, true)
          or string.find(rest, country, 1, true) then
          pick = r
          break
        end
      end
    end
    coords = { lat = pick.latitude, lon = pick.longitude }
    coordsFor = address
    fetchCurrent()
  end)
end

local function refresh()
  lastFetch = now()
  local address = currentAddress()
  if address == "" then
    fail("no location set")
    return
  end
  if coords and coordsFor == address then
    fetchCurrent()
  else
    geocode(address)
  end
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function update()
  if not ready then
    -- the sprites may get extracted later, so keep checking
    if not settingUp and now() - (lastSetupTry or 0) >= SETUP_RETRY_SECONDS then
      setup()
    end
    return
  end

  refreshWallpaperColor()
  if lastFetch == nil or now() - lastFetch >= REFRESH_SECONDS or currentAddress() ~= (coordsFor or "") then
    refresh()
  end
  redraw()

  if #frames > 1 then
    frameIndex = frameIndex % #frames + 1
    show()
  end
end

if dataDir then
  -- drop renders left over from a previous run
  for _, name in noctalia.listDir(dataDir) or {} do
    if string.match(name, "^hud%-%d+%-%d%.png$") or string.match(name, "^hud%-%d+%.png$") then
      noctalia.removeFile(`{dataDir}/{name}`)
    end
  end
end

refreshWallpaperColor()
show()
setup()
refresh()
