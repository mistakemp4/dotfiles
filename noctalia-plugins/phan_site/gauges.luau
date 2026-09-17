--!nonstrict
-- sprites: EN.CPK CALENDAR/GOODGAUGE.PAC -> p5_good_ps4.spd; positions matched to a 1504x734 screenshot

local W, ROW_GAP = 480, -16
local RENDER_SCALE = 2
local SPRITES_DIR = "~/.local/share/p5-game-assets/agent-a/spd/good"
local COLOR_FILE = "~/.cache/noctalia/phantom-calendar-color.txt"
local GAME_RED = "#e93423"
local PAPER, JET = "#fbf7f2", "#000000"
-- alacritty opacity
local BLACK_ALPHA = 0.88
local QUESTION_FONT = "P5 Dialogue, FOT-Skip Std"

local SPR = {
  base = { 1, 930, 156 }, fill = { 2, 816, 102 }, yes = { 28, 132, 96 }, q = { 29, 270, 270 }, logo = { 40, 386, 164 },
}
local DIGIT = { front = 4, back = 14, w = 160, h = 222 }
local DOT = { front = 25, back = 27, w = 76, h = 74 }
local PERCENT = { front = 24, back = 26, w = 150, h = 158 }

-- { cx, cy, scale, rotation }
local LAYOUT = {
  base = { 599, 263, 1, 0 }, q = { 199, 153, 0.97, 7 }, logo = { 520.1, 65, 1, -16 }, yes = { 1031, 305, 1, 0 },
}
local FILL_X, FILL_Y = 173, 225
-- sx: the game squeezes banner text to 65.7% width
local QUESTION = { cx = 1034, cy = 103.8, rot = -7, x = -743, baseline = 22, size = 96, stroke = 32, sx = 0.657 }
local NUMBER = {
  unitX = 1412, unitY = 270, fracAdvance = 86.5, fracY = 267.5, fracScale = 0.745,
  dotAdvance = 64.5, dotY = 312, dotScale = 0.97, intAdvance = 44.5, intY = 247, intScale = 0.98, intStep = 77.5,
}

local POLLS = {
  { key = "cpu", question = { "Is your CPU working ", "hard enough", "?" } },
  { key = "temp", question = { "Is it getting ", "hot", " in here?" } },
  { key = "ram", question = { "Is your ", "memory", " full?" } },
}

noctalia.setUpdateInterval(2000)

local dataDir = noctalia.pluginDataDir()
local pluginDir = noctalia.pluginDir()
local hasRsvg = noctalia.commandExists("rsvg-convert")
local fontsConf = dataDir and `{dataDir}/fonts.conf`

local shownPath, shownKey = nil, nil
local rendering = false
local hasSprites = false

local function sh(s)
  return "'" .. (string.gsub(s, "'", "'\\''")) .. "'"
end

local function xml(s)
  return (string.gsub(s, "[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

local function pollBounds()
  local x0, y0, x1, y1 = math.huge, math.huge, -math.huge, -math.huge
  local function add(cx, cy, w, h, rot)
    local r = math.rad(math.abs(rot))
    local ew, eh = w * math.cos(r) + h * math.sin(r), w * math.sin(r) + h * math.cos(r)
    x0, y0 = math.min(x0, cx - ew / 2), math.min(y0, cy - eh / 2)
    x1, y1 = math.max(x1, cx + ew / 2), math.max(y1, cy + eh / 2)
  end
  for name, l in LAYOUT do
    local s = SPR[name]
    add(l[1], l[2], s[2] * l[3], s[3] * l[3], l[4])
  end
  add(NUMBER.unitX, NUMBER.unitY, PERCENT.w, PERCENT.h, 0)
  add(768, 136, 960, 90, QUESTION.rot)
  return x0 - 4, y0 - 4, x1 + 4, y1 + 4
end

local PX0, PY0, PX1, PY1 = pollBounds()
local ROW_SCALE = W / (PX1 - PX0)
local ROW_H = (PY1 - PY0) * ROW_SCALE
local H = math.ceil(ROW_H * 3 + ROW_GAP * 2)

local function accent()
  if noctalia.getConfig("color") == "wallpaper" then
    local text = noctalia.readFile(COLOR_FILE)
    local color = text and string.match(text, "#%x%x%x%x%x%x")
    if color then
      return color
    end
  end
  return GAME_RED
end

local function readings()
  local stats = noctalia.systemStats()
  if not stats then
    return nil
  end
  return { cpu = stats.cpu.usagePercent, temp = stats.cpu.tempC, ram = stats.ram.usagePercent }
end

local function valueText(value)
  local v = math.max(value or 0, 0)
  if v >= 99.95 then
    return tostring(math.floor(v + 0.5))
  end
  return string.format("%04.1f", v)
end

local function place(id, w, h, cx, cy, scale, rot, filter)
  return string.format(
    '<g transform="translate(%g %g) rotate(%g) scale(%g)"><image x="%g" y="%g" width="%d" height="%d" href="img/good/spr_%03d.png"%s/></g>',
    cx, cy, rot, scale, -w / 2, -h / 2, w, h, id, if filter then ` filter="url(#{filter})"` else ""
  )
end

local function piece(name, filter)
  local s, l = SPR[name], LAYOUT[name]
  return place(s[1], s[2], s[3], l[1], l[2], l[3], l[4], filter)
end

local function number(text, isTemp)
  local backs, fronts = {}, {}
  local function glyph(front, back, w, h, cx, cy, scale)
    table.insert(backs, place(back, w, h, cx, cy, scale, 0, "black"))
    table.insert(fronts, place(front, w, h, cx, cy, scale, 0, "tint"))
  end

  if isTemp then
    -- no degree sprite
    table.insert(backs, string.format('<g transform="rotate(14 %g %g)"><ellipse cx="%g" cy="%g" rx="17" ry="24" fill="none" stroke="%s" stroke-width="22"/></g>', NUMBER.unitX - 30, NUMBER.unitY - 72, NUMBER.unitX - 30, NUMBER.unitY - 72, JET))
    table.insert(fronts, string.format('<g transform="rotate(14 %g %g)"><ellipse cx="%g" cy="%g" rx="17" ry="24" fill="none" stroke="currentColor" stroke-width="10" filter="url(#tint)"/></g>', NUMBER.unitX - 30, NUMBER.unitY - 72, NUMBER.unitX - 30, NUMBER.unitY - 72))
  else
    glyph(PERCENT.front, PERCENT.back, PERCENT.w, PERCENT.h, NUMBER.unitX, NUMBER.unitY, 1)
  end

  local ints, frac = string.match(text, "^(%d+)%.(%d)$")
  ints = ints or text
  local x = NUMBER.unitX
  if frac then
    x -= NUMBER.fracAdvance
    local d = tonumber(frac)
    glyph(DIGIT.front + d, DIGIT.back + d, DIGIT.w, DIGIT.h, x, NUMBER.fracY, NUMBER.fracScale)
    x -= NUMBER.dotAdvance
    glyph(DOT.front, DOT.back, DOT.w, DOT.h, x, NUMBER.dotY, NUMBER.dotScale)
    x -= NUMBER.intAdvance
  else
    x -= NUMBER.fracAdvance + 10
  end
  for i = #ints, 1, -1 do
    local d = tonumber(string.sub(ints, i, i))
    glyph(DIGIT.front + d, DIGIT.back + d, DIGIT.w, DIGIT.h, x, NUMBER.intY, NUMBER.intScale)
    x -= NUMBER.intStep
  end
  return table.concat(backs, "\n") .. "\n" .. table.concat(fronts, "\n")
end

local function meter(i, poll, value, color)
  local y = (i - 1) * (ROW_H + ROW_GAP)
  local pct = math.clamp((value or 0) / 100, 0, 1)
  local q = poll.question
  local fillW = SPR.fill[2] * pct
  return table.concat({
    string.format('<g transform="translate(0 %g) scale(%g) translate(%g %g)">', y, ROW_SCALE, -PX0, -PY0),
    piece("base"),
    string.format('<clipPath id="fill%d"><rect x="%g" y="%g" width="%g" height="%d"/></clipPath>', i, FILL_X, FILL_Y, fillW, SPR.fill[3]),
    if fillW > 0
      then string.format('<image x="%g" y="%g" width="%d" height="%d" href="img/good/spr_%03d.png" filter="url(#tint)" clip-path="url(#fill%d)"/>',
        FILL_X, FILL_Y, SPR.fill[2], SPR.fill[3], SPR.fill[1], i)
      else "",
    piece("q"),
    piece("logo"),
    string.format('<g transform="translate(%g %g) rotate(%g) scale(%g 1)"><text x="%g" y="%g" font-family="%s" font-size="%g" fill="%s" stroke="%s" stroke-width="%g" stroke-linejoin="round" paint-order="stroke">%s<tspan fill="%s">%s</tspan>%s</text></g>',
      QUESTION.cx, QUESTION.cy, QUESTION.rot, QUESTION.sx, QUESTION.x / QUESTION.sx, QUESTION.baseline, QUESTION_FONT, QUESTION.size, PAPER, JET, QUESTION.stroke,
      xml(q[1]), color, xml(q[2]), xml(q[3])),
    piece("yes"),
    number(valueText(value), poll.key == "temp"),
    "</g>",
  }, "\n")
end

local function buildSvg(values, color)
  local out = {
    string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" color="%s">', W, H, W, H, color),
    string.format('<defs><filter id="tint" color-interpolation-filters="sRGB"><feFlood flood-color="%s"/><feComposite in2="SourceAlpha" operator="in"/></filter>', color),
    '<filter id="black" color-interpolation-filters="sRGB"><feFlood flood-color="#000000"/><feComposite in2="SourceAlpha" operator="in"/></filter>',
    -- flatten first so overlapping blacks don't stack darker
    string.format('<filter id="glass" filterUnits="userSpaceOnUse" x="0" y="0" width="%d" height="%d" color-interpolation-filters="sRGB">', W, H),
    '<feColorMatrix in="SourceGraphic" type="matrix" values="0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 8 8 8 0 0"/>',
    string.format('<feComponentTransfer result="alpha"><feFuncA type="linear" slope="%g" intercept="%g"/></feComponentTransfer>', 1 - BLACK_ALPHA, BLACK_ALPHA),
    '<feComposite in="SourceGraphic" in2="alpha" operator="in"/></filter></defs>',
    '<g filter="url(#glass)">',
  }
  for i, poll in POLLS do
    table.insert(out, meter(i, poll, values[poll.key], color))
  end
  table.insert(out, "</g></svg>")
  return table.concat(out, "\n")
end

local function render()
  if rendering or not dataDir or not hasRsvg or not hasSprites then
    return
  end
  local values = readings()
  if not values then
    return
  end
  local color = accent()
  local key = table.concat({ color, valueText(values.cpu), valueText(values.temp), valueText(values.ram) }, "|")
  if key == shownKey then
    return
  end

  rendering = true
  local svgPath = `{dataDir}/gauges.svg`
  -- new name defeats the image cache
  local pngPath = `{dataDir}/gauges-{noctalia.nowMs()}.png`
  noctalia.writeFile(svgPath, buildSvg(values, color))
  noctalia.runAsync(`FONTCONFIG_FILE={sh(fontsConf)} rsvg-convert -w {W * RENDER_SCALE} {sh(svgPath)} -o {sh(pngPath)}`, function(res)
    rendering = false
    if res.exitCode ~= 0 then
      noctalia.log(`phan_site gauges: rsvg-convert failed ({res.exitCode}) {res.stderr}`)
      return
    end
    local old = shownPath
    shownPath, shownKey = pngPath, key
    desktopWidget.render(ui.image({ path = pngPath, width = W, height = H, fit = "contain" }))
    if old then
      noctalia.removeFile(old)
    end
  end, 15000)
end

function update()
  render()
end

if dataDir then
  noctalia.writeFile(fontsConf, table.concat({
    '<?xml version="1.0"?>',
    '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">',
    "<fontconfig>",
    '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>',
    `  <dir>{pluginDir}/assets</dir>`,
    `  <cachedir>{dataDir}/fccache</cachedir>`,
    "</fontconfig>",
  }, "\n"))
  local source = noctalia.expandPath(SPRITES_DIR)
  if noctalia.fileExists(`{source}/spr_040.png`) then
    -- rsvg-convert only loads images next to the svg
    noctalia.runAsync(`mkdir -p {sh(dataDir .. "/img/good")} && cp -f {sh(source)}/spr_0[0-4][0-9].png {sh(dataDir .. "/img/good")}/`, function(res)
      hasSprites = res.exitCode == 0
      render()
    end, 15000)
  else
    noctalia.log(`phan_site gauges: poll sprites not found in {source} (extract CALENDAR/GOODGAUGE.PAC from your own P5R)`)
  end
  for _, name in noctalia.listDir(dataDir) or {} do
    if string.match(name, "^gauges%-%d+%.png$") then
      noctalia.removeFile(`{dataDir}/{name}`)
    end
  end
end

if not hasRsvg then
  noctalia.log("phan_site gauges: rsvg-convert not found (install librsvg)")
end
noctalia.log(`phan_site gauges: widget size {W}x{H}`)
desktopWidget.render(ui.column({}, {}))
render()
