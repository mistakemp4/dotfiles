--!nonstrict
local REFRESH_SECONDS = 15 * 60
local SETUP_RETRY_SECONDS = 60
local SVG_W, SVG_H = 640, 400
-- layout is in 1920x1080 screenshot pixels
local ORIGIN_X, ORIGIN_Y = -39, 2
local SHOW_W, SHOW_H = 681, 426
local RENDER_W = 1536
local WEATHER_FRAMES = 3
local DEFAULT_ASSETS = "~/.local/share/p5-game-assets/dump/P5_FIELD_DAY"
local COLOR_FILE = "~/.cache/noctalia/phantom-calendar-color.txt"
local GAME_RED = "#e6191e"
local DARK = "#1a0d0a"

-- P5_FIELD_DAY.SPD ids; weather 0 sunny, 1 rain, 2 cloudy, 3 snow
local WEATHER_CARD = 96
local WEATHER_ICONS = { [0] = { 97, 109, 110 }, [1] = { 98, 111, 112 }, [2] = { 99, 113, 114 }, [3] = { 100, 115, 116 } }
local WEEKDAY = { Sun = 0, Mon = 1, Tue = 2, Wed = 3, Thu = 4, Fri = 5, Sat = 6 }
local TIME_OF_DAY = { EARLY_MORNING = 0, MORNING = 1, DAYTIME = 2, LUNCHTIME = 3, AFTERNOON = 4, AFTER_SCHOOL = 5, EVENING = 6, LATE_NIGHT = 7 }
local BANNERS = {
  rainy_season = 101, typhoon = 102, pollen = 103, torrential_rain = 105,
  heat_wave = 106, flu_season = 107, hot_night = 117, cold_wave = 300,
}

-- { cx, cy, scale, rotation }
local LAYOUT = {
  month = { 95, 92, 0.45, -6 },
  tens = { 188, 88, 0.42, -4 },
  ones = { 266, 82, 0.42, -3 },
  single = { 227, 85, 0.42, -3 },
  weather = { 365, 62, 0.42, 10 },
  weekday = { 279, 155, 0.47, -26 },
  timeOfDay = { 150, 262, 0.43, -24 },   -- x is recomputed per-day, see timeOfDayLayout
  banner = { 445, 188, 0.46, -5 },
}

local HOLIDAYS = {
  halloween = {
    month = 230,
    numerals = { [0] = 219, [1] = 220, [2] = 221, [3] = 222, [4] = 223, [5] = 224, [6] = 225, [7] = 226, [8] = 227, [9] = 228 },
    extras = { { 231, 398, 120, 0.42, 0 }, { 232, 398, 164, 0.55, 0 }, { 233, 30, 186, 0.5, -12 }, { 235, 424, 150, 0.42, 8 }, { 236, 20, 40, 0.42, 0 } },
  },
  christmas = {
    month = 149,
    extras = { { 140, 226, 6, 0.5, -4 }, { 144, 436, 8, 0.42, 10 }, { 146, 26, 50, 0.42, -10 }, { 147, 170, 214, 0.42, 0 }, { 145, 438, 138, 0.42, 20 } },
  },
  newyear = {
    month = 244,
    numerals = { [1] = 242, [2] = 243, [3] = 239, [4] = 240, [5] = 241 },
    icons = { [0] = { 251, 252, 253 }, [1] = { 297, 298, 299 }, [2] = { 254, 255, 256 }, [3] = { 257, 258, 260 } },
    extras = { { 245, 12, 70, 0.42, 0 }, { 246, 440, 150, 0.42, 0 }, { 248, 40, 206, 0.42, 0 }, { 247, 424, 12, 0.42, 0 }, { 249, 350, 206, 0.38, 0 } },
  },
  valentine = {
    tuesday = 264,
    extras = { { 271, 150, 136, 0.3, -6 }, { 272, 312, 118, 0.3, 12 }, { 265, 230, 112, 0.42, -8 }, { 266, 318, 108, 0.42, 0 }, { 267, 336, 136, 0.36, -20 }, { 268, 304, 138, 0.36, 15 } },
  },
  whiteday = {
    extras = { { 276, 226, 112, 0.42, -8 }, { 277, 226, 122, 0.42, -8 }, { 278, 318, 138, 0.36, 0 }, { 279, 346, 140, 0.36, 0 }, { 280, 420, 118, 0.42, 0 } },
  },
  hanami = {
    extras = { { 155, 34, 36, 0.42, 0 }, { 156, 430, 132, 0.42, 0 }, { 157, 186, 232, 0.36, 0 }, { 158, 330, -2, 0.34, 0 }, { 160, 454, 40, 0.42, 20 }, { 161, 20, 190, 0.42, 0 }, { 162, 250, 236, 0.42, 0 }, { 164, 150, -8, 0.42, 0 } },
  },
  hanami_night = {
    extras = { { 195, 438, 150, 0.42, 6 }, { 196, 30, 40, 0.42, 0 }, { 197, 340, 0, 0.36, 0 }, { 198, 190, 230, 0.36, 0 }, { 199, 24, 200, 0.36, 0 }, { 200, 460, 60, 0.42, 30 } },
  },
  fireworks = {
    extras = { { 210, 34, 20, 0.36, 0 }, { 208, 440, 4, 0.34, 0 }, { 211, 120, 232, 0.3, 0 }, { 212, 470, 110, 0.3, 0 }, { 206, 430, 176, 0.42, 18 } },
  },
}

noctalia.setUpdateInterval(1000)

-- builtin sysmon widgets need Anton
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

-- https://open-meteo.com/en/docs
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

local function holidayFor(month, day, tod)
  if month == 10 and day == 31 then
    return "halloween"
  elseif month == 12 and (day == 24 or day == 25) then
    return "christmas"
  elseif month == 1 and day <= 5 then
    return "newyear"
  elseif month == 2 and day == 14 then
    return "valentine"
  elseif month == 3 and day == 14 then
    return "whiteday"
  elseif (month == 3 and day >= 25) or (month == 4 and day <= 10) then
    return if tod >= TIME_OF_DAY.EVENING then "hanami_night" else "hanami"
  elseif month == 8 and day == 20 then
    return "fireworks"
  end
  return nil
end

-- first match wins; °C, mm/h, km/h
local function bannerFor(month, day, w)
  if not w then
    return nil
  end
  if w.gusts >= 90 then
    return "typhoon"
  elseif w.rainPerHour >= 20 then
    return "torrential_rain"
  elseif w.temp >= 35 then
    return "heat_wave"
  elseif not w.isDay and w.temp >= 25 then
    return "hot_night"
  elseif w.temp <= -5 then
    return "cold_wave"
  elseif w.condition == 1 and (month == 6 or (month == 7 and day <= 15)) then
    return "rainy_season"
  elseif (month == 3 or month == 4) and w.condition ~= 1 and w.condition ~= 3 then
    return "pollen"
  elseif month == 12 or month <= 2 then
    return "flu_season"
  end
  return nil
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

local function tintFilter(id, color)
  return string.format(
    '<filter id="%s" color-interpolation-filters="sRGB"><feFlood flood-color="%s"/><feComposite in2="SourceAlpha" operator="in"/></filter>',
    id, color
  )
end

local function retintFilter(id, color)
  local r = tonumber(string.sub(color, 2, 3), 16) / 255 * 1.06
  local g = tonumber(string.sub(color, 4, 5), 16) / 255 * 1.06
  local b = tonumber(string.sub(color, 6, 7), 16) / 255 * 1.06
  return string.format(
    '<filter id="%s" color-interpolation-filters="sRGB"><feColorMatrix type="matrix" values="%g 0 0 0 0 %g 0 0 0 0 %g 0 0 0 0 1.5 -1.5 0 0 0"/><feComposite in2="SourceAlpha" operator="in"/><feComposite in2="SourceGraphic" operator="over"/></filter>',
    id, r, g, b
  )
end

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

-- How far the time-of-day sticker's right edge reaches past the weekday's left
-- edge. Tuned by eye against an in-game screenshot on Evening + THURSDAY.
local TOD_OVERLAP = 76

-- The weekday and time-of-day sprites are different widths per day and per time
-- of day (SUNDAY 522px vs WEDNESDAY 618px; AfterSchool 256px vs Lunch 338px) and
-- every sprite is centre-anchored, so a fixed x makes the overlap swing by ~40px
-- across combinations. Anchor the time-of-day to the weekday's actual left edge
-- instead, so the overlap looks the same every day.
local function timeOfDayLayout(s)
  local base = LAYOUT.timeOfDay
  local weekday, tod = sizes[67 + s.weekday], sizes[125 + s.timeOfDay]
  if not weekday or not tod then
    return base
  end
  local weekdayLeft = LAYOUT.weekday[1] - weekday.w * LAYOUT.weekday[3] / 2
  local todHalf = tod.w * base[3] / 2
  return { weekdayLeft + TOD_OVERLAP - todHalf, base[2], base[3], base[4] }
end

local function elements(s, frame)
  local holiday = if s.holiday then HOLIDAYS[s.holiday] else {}
  local numerals = holiday.numerals or {}

  local list = {
    { layout = LAYOUT.month, layers = { { s.month }, { 12 + s.month, "black" }, { holiday.month or (24 + s.month) } } },
  }
  local function digit(d, layout)
    table.insert(list, { layout = layout, layers = { { 37 + d }, { 47 + d, "black" }, { numerals[d] or (57 + d) } } })
  end
  if s.day >= 10 then
    digit(math.floor(s.day / 10), LAYOUT.tens)
    digit(s.day % 10, LAYOUT.ones)
  else
    digit(s.day, LAYOUT.single)
  end
  if s.weather then
    local icons = (holiday.icons or WEATHER_ICONS)[s.weather.condition]
    table.insert(list, { layout = LAYOUT.weather, layers = { { WEATHER_CARD }, false, { icons[frame + 1], "black" } } })
  end
  local w = s.weekday
  local letters = if holiday.tuesday and w == 2 then holiday.tuesday else 287 + w
  table.insert(list, { layout = LAYOUT.weekday, layers = { { 67 + w }, { 74 + w, "black" }, { 81 + w, "accent" }, { letters, "black" } } })
  local t = s.timeOfDay
  table.insert(list, { layout = timeOfDayLayout(s), layers = { { 88 + t }, { 125 + t, "dark" } } })
  return list, holiday.extras or {}
end

local function buildSvg(s, frame)
  local out = {
    string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">', SVG_W, SVG_H, SVG_W, SVG_H),
    "<defs>" .. tintFilter("black", "#000") .. tintFilter("dark", DARK) .. tintFilter("accent", s.accent)
      .. retintFilter("banner", s.accent) .. "</defs>",
    string.format('<g transform="translate(%d %d)">', ORIGIN_X, ORIGIN_Y),
  }
  -- white bases first so they merge into one sticker
  local list, extras = elements(s, frame)
  local passes = { {}, {}, {}, {} }
  for pass = 1, 4 do
    for _, element in list do
      local layer = element.layers[pass]
      if layer then
        table.insert(passes[pass], sprite(layer[1], element.layout, layer[2]))
      end
    end
  end
  local whites, blacks = table.concat(passes[1], "\n"), table.concat(passes[2], "\n")

  if s.blackOpacity < 1 then
    -- cut black out of the white sticker, fade it as one group
    table.insert(out, string.format(
      '<mask id="knockout" maskUnits="userSpaceOnUse" x="%d" y="%d" width="%d" height="%d"><rect x="%d" y="%d" width="%d" height="%d" fill="#fff"/>%s</mask>',
      -ORIGIN_X, -ORIGIN_Y, SVG_W, SVG_H, -ORIGIN_X, -ORIGIN_Y, SVG_W, SVG_H, blacks
    ))
    table.insert(out, `<g mask="url(#knockout)">{whites}</g>`)
    table.insert(out, `<g opacity="{s.blackOpacity}">{blacks}</g>`)
  else
    table.insert(out, whites)
    table.insert(out, blacks)
  end
  table.insert(out, table.concat(passes[3], "\n"))
  for _, extra in extras do
    table.insert(out, sprite(extra[1], { extra[2], extra[3], extra[4], extra[5] }, nil))
  end
  table.insert(out, table.concat(passes[4], "\n"))
  if s.banner then
    table.insert(out, sprite(BANNERS[s.banner], LAYOUT.banner, if s.accent ~= GAME_RED then "banner" else nil))
  end
  table.insert(out, "</g></svg>")
  return table.concat(out, "\n")
end

local function currentState()
  local weekday = WEEKDAY[noctalia.formatTime("%a")] or 0
  local month = tonumber(noctalia.formatTime("%m")) or 1
  local day = tonumber(noctalia.formatTime("%d")) or 1

  local previewMonth, previewDay = string.match(noctalia.getConfig("preview_date") or "", "^(%d%d?)-(%d%d?)$")
  if previewMonth then
    month, day = tonumber(previewMonth), tonumber(previewDay)
  end

  local tod = timeOfDay(tonumber(noctalia.formatTime("%H")) or 0, weekday == 0 or weekday == 6)
  local banner = bannerFor(month, day, weather)
  local previewBanner = noctalia.getConfig("preview_banner") or "none"
  if BANNERS[previewBanner] then
    banner = previewBanner
  end

  return {
    month = month,
    day = day,
    weekday = weekday,
    timeOfDay = tod,
    weather = weather,
    accent = weekdayColor(),
    blackOpacity = math.clamp(tonumber(noctalia.getConfig("black_opacity")) or 1, 0, 1),
    holiday = holidayFor(month, day, tod),
    banner = banner,
  }
end

local function contentKey(s)
  return table.concat({
    s.month, s.day, s.weekday, s.timeOfDay, s.accent, s.blackOpacity, s.holiday or "", s.banner or "",
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
    -- new name defeats the image cache
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

  -- rsvg-convert refuses images outside the svg's dir, even symlinks
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

local function fail(detail)
  weather = nil
  noctalia.log(`phantom_calendar: {detail}`)
  redraw()
end

local function fetchCurrent()
  local url = "https://api.open-meteo.com/v1/forecast"
    .. `?latitude={coords.lat}&longitude={coords.lon}`
    .. "&current=weather_code,temperature_2m,precipitation,wind_gusts_10m,is_day"
    .. "&temperature_unit=celsius&wind_speed_unit=kmh&precipitation_unit=mm"

  noctalia.http({ url = url }, function(res)
    if not res.ok or res.status >= 400 then
      fail(`forecast request failed ({res.status})`)
      return
    end
    local data = noctalia.json.decode(res.body)
    local current = type(data) == "table" and data.current or nil
    if type(current) ~= "table" or type(current.weather_code) ~= "number" then
      fail("unexpected forecast response")
      return
    end
    -- current values cover `interval` seconds
    local interval = if type(current.interval) == "number" and current.interval > 0 then current.interval else 3600
    weather = {
      condition = conditionFor(current.weather_code),
      temp = current.temperature_2m or 0,
      rainPerHour = (current.precipitation or 0) * 3600 / interval,
      gusts = current.wind_gusts_10m or 0,
      isDay = current.is_day ~= 0,
    }
    redraw()
  end)
end

local function geocode(address)
  -- open-meteo only searches place names
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

function update()
  if not ready then
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
