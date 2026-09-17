--!nonstrict
local REFRESH_SECONDS = 15 * 60

noctalia.setUpdateInterval(60 * 1000)

local status = noctalia.tr("status.loading")
local weather = nil
local coords, coordsFor = nil, nil
local lastFetch = nil

local function now()
  return tonumber(noctalia.formatTime("%s")) or 0
end

local function shellSetting(path)
  local ok, value = pcall(noctalia.getSetting, path)
  if ok then
    return value
  end
  return nil
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

local function useFahrenheit()
  local unit = noctalia.getConfig("unit") or "auto"
  if unit == "auto" then
    return shellSetting("weather.unit") ~= "metric"
  end
  return unit == "fahrenheit"
end

-- https://open-meteo.com/en/docs
local function describe(code, isDay)
  if code == 0 then
    return isDay and "sun" or "moon", "Clear"
  elseif code == 1 then
    return isDay and "sun" or "moon", "Mostly clear"
  elseif code == 2 then
    return "cloud-sun", "Partly cloudy"
  elseif code == 3 then
    return "cloud", "Cloudy"
  elseif code == 45 or code == 48 then
    return "cloud-fog", "Foggy"
  elseif code >= 51 and code <= 57 then
    return "cloud-rain", "Drizzle"
  elseif code >= 61 and code <= 67 then
    return "cloud-rain", "Rain"
  elseif code >= 71 and code <= 77 then
    return "cloud-snow", "Snow"
  elseif code >= 80 and code <= 82 then
    return "cloud-rain", "Showers"
  elseif code == 85 or code == 86 then
    return "cloud-snow", "Snow showers"
  elseif code >= 95 then
    return "cloud-storm", "Thunderstorm"
  end
  return "cloud", "Unknown"
end

local function render()
  local color = noctalia.getConfig("color") or "on_surface"
  local rows = {}

  if not weather then
    table.insert(rows, ui.label({ text = status, fontSize = 20, color = color, textAlign = "center" }))
  else
    -- the persona font's ° is mostly empty space and breaks centering
    local unitText = weather.fahrenheit and "°F" or "°C"
    table.insert(rows, ui.row({ gap = 12, align = "center", justify = "center" }, {
      ui.glyph({ name = weather.glyph, size = 60, color = color }),
      ui.label({ text = tostring(weather.temp), fontSize = 60, color = color }),
      ui.label({ text = unitText, fontSize = 34, fontFamily = "JetBrains Mono", color = color }),
    }))
    table.insert(rows, ui.label({ text = weather.condition, fontSize = 26, color = color, textAlign = "center" }))

    if #weather.days > 0 then
      local left, right = {}, {}
      for _, day in weather.days do
        table.insert(left, ui.row({ gap = 10, align = "center" }, {
          ui.label({ text = day.name, fontSize = 22, color = color }),
          ui.glyph({ name = day.glyph, size = 24, color = color }),
        }))
        table.insert(right, ui.label({ text = `{day.low} / {day.high}`, fontSize = 22, color = color }))
      end
      table.insert(rows, ui.row({ gap = 18, align = "start", justify = "center" }, {
        ui.column({ gap = 4, align = "end" }, left),
        ui.column({ gap = 4, align = "start" }, right),
      }))
    end
  end

  desktopWidget.render(ui.column({ gap = 10, align = "center", justify = "center" }, rows))
end

local function fail(key, detail)
  status = noctalia.tr(key)
  weather = nil
  if detail then
    noctalia.log(`centered_weather: {detail}`)
  end
  render()
end

local function fetchForecast()
  local fahrenheit = useFahrenheit()
  local days = noctalia.getConfig("forecast_days") or 3
  local url = "https://api.open-meteo.com/v1/forecast"
    .. `?latitude={coords.lat}&longitude={coords.lon}`
    .. "&current=temperature_2m,weather_code,is_day"
    .. "&daily=weather_code,temperature_2m_max,temperature_2m_min"
    .. `&temperature_unit={fahrenheit and "fahrenheit" or "celsius"}`
    .. `&timezone=auto&timeformat=unixtime&forecast_days={days + 1}`

  noctalia.http({ url = url }, function(res)
    if not res.ok or res.status >= 400 then
      fail("status.error", `forecast request failed ({res.status})`)
      return
    end
    local data = noctalia.json.decode(res.body)
    if type(data) ~= "table" or type(data.current) ~= "table" or type(data.daily) ~= "table" then
      fail("status.error", "unexpected forecast response")
      return
    end

    local glyph, condition = describe(data.current.weather_code, data.current.is_day == 1)
    local result = {
      temp = math.round(data.current.temperature_2m),
      fahrenheit = fahrenheit,
      glyph = glyph,
      condition = condition,
      days = {},
    }
    for i = 2, #data.daily.time do
      local dayGlyph = describe(data.daily.weather_code[i], true)
      table.insert(result.days, {
        -- noon avoids timezone day shifts
        name = noctalia.formatTime("%a", data.daily.time[i] + 12 * 3600),
        glyph = dayGlyph,
        low = math.round(data.daily.temperature_2m_min[i]),
        high = math.round(data.daily.temperature_2m_max[i]),
      })
    end
    weather = result
    render()
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
      fail("status.error", `geocoding request failed ({res.status})`)
      return
    end
    local data = noctalia.json.decode(res.body)
    local results = type(data) == "table" and data.results or nil
    if type(results) ~= "table" or #results == 0 then
      fail("status.not_found", "no geocoding results")
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
    fetchForecast()
  end)
end

local function refresh()
  lastFetch = now()
  local address = currentAddress()
  if address == "" then
    fail("status.no_location", nil)
    return
  end
  if coords and coordsFor == address then
    fetchForecast()
  else
    geocode(address)
  end
end

function update()
  if lastFetch == nil or now() - lastFetch >= REFRESH_SECONDS or currentAddress() ~= (coordsFor or "") then
    refresh()
  end
end

render()
refresh()
