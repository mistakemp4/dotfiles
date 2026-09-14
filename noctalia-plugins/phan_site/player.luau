--!nonstrict
-- Persona 5 Phan-Site style now-playing speech bubble for the active MPRIS player; click it to play/pause.
-- Player state comes from busctl and the bubble is SVG rendered with rsvg-convert, in three tiles so only
-- what changes gets redrawn: the art corner and the title band per track, the bottom band (artist,
-- progress, time) every second. A title too long for its band scrolls as pre-rendered marquee frames made
-- with ImageMagick, since desktop widget images can't be clipped or offset.

local W, H = 420, 150
local SPLIT_X, SPLIT_Y = 118, 62 -- title band: x >= SPLIT_X, y < SPLIT_Y
local SCALE = 2 -- render pixels per logical pixel
local SCAN_SECONDS = 5
local COLOR_FILE = "~/.cache/noctalia/phantom-calendar-color.txt"
local FALLBACK_ACCENT = "#e6191e"
local PAPER, JET, INK_SOFT, TRACK = "#fbf7f2", "#0d0908", "#5b4a44", "#2b1a15"
local MPRIS = "org.mpris.MediaPlayer2."
-- rough text budgets in half-width units (CJK counts double)
local TITLE_UNITS, ARTIST_UNITS = 200, 44
-- marquee, in render pixels
local MARQUEE_PAD, MARQUEE_GAP, MARQUEE_STEP, MARQUEE_AVAIL = 8, 96, 4, 562
local MARQUEE_FRAME_MS, MARQUEE_HOLD_MS = 50, 1500

-- art tile, title band (one frame, or marquee frames) for a track; prints the frame count
local HEAD_SCRIPT = [[
set -e
export FONTCONFIG_FILE=@FONTS@
cd @DIR@
rsvg-convert -w @ART_W@ art.svg -o @ART_OUT@
rsvg-convert -w @BAND_W@ band.svg -o band.png
rsvg-convert -w 4000 title.svg -o title-raw.png
read tw tx <<EOF
$(magick title-raw.png -trim -format '%w %X' info:)
EOF
tx=${tx#+}
magick title-raw.png -crop "${tw}x@BAND_H@+${tx}+0" +repage title.png
if [ "$tw" -le @AVAIL@ ]; then
  magick band.png title.png -geometry +@PAD@+0 -compose atop -composite @PREFIX@-000.png
  echo 1
else
  period=$((tw + @GAP@))
  n=$(( (period + @STEP@ - 1) / @STEP@ ))
  magick title.png -background none -gravity west -extent "${period}x@BAND_H@" strip1.png
  magick strip1.png strip1.png +append strip.png
  magick band.png -duplicate $((n - 1)) null: \( strip.png -duplicate $((n - 1)) -virtual-pixel transparent -define distort:viewport=@BAND_W@x@BAND_H@+0+0 -distort SRT "0,0 1 0 %[fx:@PAD@-t*@STEP@],0" \) -compose atop -layers composite @PREFIX@-%03d.png
  echo "$n"
fi
]]

noctalia.setUpdateInterval(1000)

local dataDir = noctalia.pluginDataDir()
local pluginDir = noctalia.pluginDir()
local hasTools = noctalia.commandExists("rsvg-convert") and noctalia.commandExists("magick")
local fontsConf = dataDir and `{dataDir}/player-fonts.conf`

local buses, lastScan = {}, nil
local active, track = nil, nil
local polling = false
local artKey, artPath, artLoading = nil, nil, false
local head = { key = nil, failedKey = nil, art = nil, gen = nil, frames = 0, busy = false, pending = false }
local bottom = { key = nil, path = nil, busy = false, pending = false }
local frameIndex, frameClock = 0, 0

local redraw, togglePlayback

local function now()
  return tonumber(noctalia.formatTime("%s")) or 0
end

local function sh(s)
  return "'" .. (string.gsub(s, "'", "'\\''")) .. "'"
end

local function xml(s)
  return (string.gsub(s, "[&<>\"]", { ["&"] = "&amp;", ["<"] = "&lt;", [">"] = "&gt;", ['"'] = "&quot;" }))
end

local function fill(template, values)
  return (string.gsub(template, "@([%w_]+)@", function(name)
    return tostring(values[name])
  end))
end

local function accent()
  local text = noctalia.readFile(COLOR_FILE)
  return (text and string.match(text, "#%x%x%x%x%x%x")) or FALLBACK_ACCENT
end

local function clip(s, maxUnits)
  local ok, result = pcall(function()
    local units, out = 0, {}
    for _, cp in utf8.codes(s) do
      units += if cp >= 0x2E80 then 2 else 1
      if units > maxUnits then
        return table.concat(out) .. "…"
      end
      table.insert(out, utf8.char(cp))
    end
    return s
  end)
  return if ok then result else s
end

local function clock(us)
  local seconds = math.floor((us or 0) / 1e6)
  return string.format("%d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- busctl --json wraps every variant as { type, data }
local function prop(props, name)
  local v = props[name]
  return if type(v) == "table" then v.data else nil
end

-- ── svg ──────────────────────────────────────────────────────────────────────

-- the whole bubble except the title; each tile renders it through its own viewBox
local function sceneBody(t, color)
  local out = {
    -- black offset shadow keeps the white bubble readable over bright wallpapers
    string.format('<polygon points="10,26 %d,10 %d,116 36,108" fill="%s" fill-opacity="0.85"/>', W, W - 12, JET),
    string.format('<polygon points="4,20 %d,4 %d,110 30,102" fill="%s"/>', W - 6, W - 18, PAPER),
    string.format('<polygon points="44,100 30,117 78,104" fill="%s"/>', PAPER),
    '<g transform="translate(62 58) rotate(-5)">',
    string.format('<rect x="-42" y="-42" width="84" height="84" fill="%s"/>', JET),
  }
  if artPath then
    table.insert(out, string.format('<image x="-38" y="-38" width="76" height="76" preserveAspectRatio="xMidYMid slice" href="%s"/>', xml(string.match(artPath, "[^/]+$"))))
  else
    table.insert(out, string.format('<rect x="-38" y="-38" width="76" height="76" fill="%s"/>', color))
  end
  table.insert(out, "</g>")

  if t then
    table.insert(out, string.format('<text x="118" y="78" font-family="FOT-Skip Std" font-size="13" fill="%s">%s</text>', INK_SOFT, xml(clip(t.artist, ARTIST_UNITS))))
    if not t.playing then
      table.insert(out, string.format('<polygon points="120,86 184,84 180,102 118,103" fill="%s"/>', color))
      table.insert(out, string.format('<text x="151" y="99" font-family="Anton" font-size="13" letter-spacing="1" text-anchor="middle" fill="%s">PAUSED</text>', JET))
    end
  end

  if t and t.lengthUs > 0 then
    local pct = math.clamp(t.positionUs / t.lengthUs, 0, 1)
    local left, right, top, bottomY, slant = 34, 296, 124, 134, 6
    local fillRight = left + (right - left) * pct
    -- dark strip so the bar and time stay readable over bright wallpapers
    table.insert(out, string.format('<polygon points="18,116 %d,113 %d,149 8,150" fill="%s" fill-opacity="0.82"/>', W, W - 10, JET))
    table.insert(out, string.format('<polygon points="%g,%d %g,%d %g,%d %g,%d" fill="%s"/>', left + slant, top, right + slant, top, right, bottomY, left, bottomY, TRACK))
    if pct > 0 then
      table.insert(out, string.format('<polygon points="%g,%d %g,%d %g,%d %g,%d" fill="%s"/>', left + slant, top, fillRight + slant, top, fillRight, bottomY, left, bottomY, color))
    end
    table.insert(out, string.format('<polygon points="%g,%d %g,%d %g,%d %g,%d" fill="none" stroke="%s" stroke-width="2"/>', left + slant, top, right + slant, top, right, bottomY, left, bottomY, PAPER))
    table.insert(out, string.format('<g transform="translate(%d 137) skewX(-10)"><text font-family="Anton" font-size="17" text-anchor="end" fill="%s">%s / %s</text></g>', W - 10, PAPER, clock(t.positionUs), clock(t.lengthUs)))
  end
  return table.concat(out, "\n")
end

local function svgDoc(body, x, y, w, h)
  return string.format('<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="%d %d %d %d">\n%s\n</svg>', w, h, x, y, w, h, body)
end

-- the title alone on a wide canvas at the bubble's baseline, so its width can be measured
local function titleDoc(title, color)
  return string.format(
    '<svg xmlns="http://www.w3.org/2000/svg" width="2000" height="%d" viewBox="0 0 2000 %d"><text x="10" y="48" font-family="FOT-Skip Std" font-size="20" fill="%s">%s</text></svg>',
    SPLIT_Y, SPLIT_Y, color, xml(clip(title, TITLE_UNITS))
  )
end

-- ── tiles ────────────────────────────────────────────────────────────────────

local function framePath(i)
  return string.format("%s/title-%s-%03d.png", dataDir, head.gen, i)
end

local function show()
  if not head.art or not bottom.path then
    return
  end
  desktopWidget.render(ui.column({ gap = 0, onClick = togglePlayback }, {
    ui.row({ gap = 0 }, {
      ui.image({ path = head.art, width = SPLIT_X, height = SPLIT_Y, fit = "stretch" }),
      ui.image({ path = framePath(frameIndex), width = W - SPLIT_X, height = SPLIT_Y, fit = "stretch" }),
    }),
    ui.image({ path = bottom.path, width = W, height = H - SPLIT_Y, fit = "stretch" }),
  }))
end

local function dropHead(art, gen)
  if art then
    noctalia.removeFile(art)
  end
  if not gen then
    return
  end
  for _, name in noctalia.listDir(dataDir) or {} do
    if string.match(name, "^title%-(%d+)%-%d+%.png$") == gen then
      noctalia.removeFile(`{dataDir}/{name}`)
    end
  end
end

local function renderHead(color)
  if head.busy then
    head.pending = true
    return
  end
  local title = if track then track.title else "Nothing playing"
  local key = table.concat({ color, if track then track.bus else "", title, artPath or "" }, "|")
  if key == head.key or key == head.failedKey then
    return
  end

  head.busy = true
  local gen = tostring(noctalia.nowMs())
  local artOut = `{dataDir}/head-{gen}.png`
  local body = sceneBody(track, color)
  noctalia.writeFile(`{dataDir}/art.svg`, svgDoc(body, 0, 0, SPLIT_X, SPLIT_Y))
  noctalia.writeFile(`{dataDir}/band.svg`, svgDoc(body, SPLIT_X, 0, W - SPLIT_X, SPLIT_Y))
  noctalia.writeFile(`{dataDir}/title.svg`, titleDoc(title, if track then JET else INK_SOFT))
  local script = fill(HEAD_SCRIPT, {
    FONTS = sh(fontsConf),
    DIR = sh(dataDir),
    ART_W = SPLIT_X * SCALE,
    ART_OUT = sh(artOut),
    BAND_W = (W - SPLIT_X) * SCALE,
    BAND_H = SPLIT_Y * SCALE,
    AVAIL = MARQUEE_AVAIL,
    PAD = MARQUEE_PAD,
    GAP = MARQUEE_GAP,
    STEP = MARQUEE_STEP,
    PREFIX = sh(`{dataDir}/title-{gen}`),
  })

  noctalia.runAsync(script, function(res)
    head.busy = false
    local frames = tonumber(string.match(res.stdout or "", "(%d+)%s*$"))
    if res.exitCode == 0 and frames and frames > 0 then
      local oldArt, oldGen = head.art, head.gen
      head.key, head.failedKey = key, nil
      head.art, head.gen, head.frames = artOut, gen, frames
      frameIndex, frameClock = 0, 0
      desktopWidget.setNeedsFrameTick(frames > 1)
      show()
      dropHead(oldArt, oldGen)
    else
      head.failedKey = key
      noctalia.log(`phan_site player: title render failed ({res.exitCode}) {res.stderr}`)
      dropHead(artOut, gen)
    end
    if head.pending then
      head.pending = false
      redraw()
    end
  end, 60000)
end

local function renderBottom(color)
  if bottom.busy then
    bottom.pending = true
    return
  end
  local key = if track
    then table.concat({ color, track.bus, track.artist, clock(track.positionUs), clock(track.lengthUs), tostring(track.playing), artPath or "" }, "|")
    else table.concat({ color, "idle", artPath or "" }, "|")
  if key == bottom.key then
    return
  end

  bottom.busy = true
  local svgPath = `{dataDir}/bottom.svg`
  -- new name every render, so the image can't be served from a stale cache
  local pngPath = `{dataDir}/bottom-{noctalia.nowMs()}.png`
  noctalia.writeFile(svgPath, svgDoc(sceneBody(track, color), 0, SPLIT_Y, W, H - SPLIT_Y))
  noctalia.runAsync(`FONTCONFIG_FILE={sh(fontsConf)} rsvg-convert -w {W * SCALE} {sh(svgPath)} -o {sh(pngPath)}`, function(res)
    bottom.busy = false
    if res.exitCode == 0 then
      local old = bottom.path
      bottom.key, bottom.path = key, pngPath
      show()
      if old then
        noctalia.removeFile(old)
      end
    else
      noctalia.log(`phan_site player: bottom render failed ({res.exitCode}) {res.stderr}`)
    end
    if bottom.pending then
      bottom.pending = false
      redraw()
    end
  end, 15000)
end

redraw = function()
  if not dataDir or not hasTools then
    return
  end
  local color = accent()
  renderHead(color)
  renderBottom(color)
end

-- album art: rsvg-convert only loads images next to the svg, so keep a copy in the data dir
local function refreshArt()
  local url = if track then track.artUrl else ""
  -- players like Brave reuse one art file name for every track, so key on the title too
  local key = url .. "|" .. (if track then track.title else "")
  if key == artKey or artLoading then
    return
  end
  if url == "" then
    artKey, artPath = key, nil
    return
  end

  artLoading = true
  local dest = `{dataDir}/art-{noctalia.nowMs()}`
  local function finish(ok)
    artLoading = false
    local old = artPath
    artKey = key
    artPath = if ok then dest else nil
    if old and old ~= artPath then
      noctalia.removeFile(old)
    end
    redraw()
  end
  if string.sub(url, 1, 7) == "file://" then
    noctalia.runAsync({ "cp", "-f", noctalia.string.urlDecode(string.sub(url, 8)), dest }, function(res)
      finish(res.exitCode == 0)
    end, 5000)
  elseif string.match(url, "^https?://") then
    noctalia.download(url, dest, finish)
  else
    finish(false)
  end
end

-- ── players ──────────────────────────────────────────────────────────────────

local function scan(done)
  noctalia.runAsync("busctl --user list --no-legend --acquired 2>/dev/null | awk '{print $1}'", function(res)
    local found = {}
    for name in string.gmatch(res.stdout or "", "[^\n]+") do
      if string.sub(name, 1, #MPRIS) == MPRIS then
        table.insert(found, name)
      end
    end
    buses, lastScan = found, now()
    done()
  end, 5000)
end

local function fetch(bus, done)
  local argv = { "busctl", "--user", "--json=short", "call", bus, "/org/mpris/MediaPlayer2",
    "org.freedesktop.DBus.Properties", "GetAll", "s", "org.mpris.MediaPlayer2.Player" }
  noctalia.runAsync(argv, function(res)
    local decoded = if res.exitCode == 0 and not res.stdoutTruncated then noctalia.json.decode(res.stdout) else nil
    local props = if type(decoded) == "table" and type(decoded.data) == "table" then decoded.data[1] else nil
    if type(props) ~= "table" then
      done(nil)
      return
    end
    local meta = prop(props, "Metadata") or {}
    local artists = prop(meta, "xesam:artist")
    done({
      bus = bus,
      title = prop(meta, "xesam:title") or "",
      artist = if type(artists) == "table" then table.concat(artists, ", ") else "",
      lengthUs = tonumber(prop(meta, "mpris:length")) or 0,
      positionUs = tonumber(prop(props, "Position")) or 0,
      playing = prop(props, "PlaybackStatus") == "Playing",
      artUrl = prop(meta, "mpris:artUrl") or "",
    })
  end, 5000)
end

-- prefer a playing player (the current one if several are), then the current one, then any
local function choose(results)
  local pick = nil
  for _, t in results do
    if t.playing and (pick == nil or t.bus == active) then
      pick = t
    end
  end
  if not pick then
    for _, t in results do
      if t.bus == active then
        pick = t
      end
    end
  end
  pick = pick or results[1]
  active, track = if pick then pick.bus else nil, pick
  refreshArt()
  redraw()
end

local function poll()
  if polling or not dataDir then
    return
  end
  polling = true
  local function readAll()
    local results, i = {}, 0
    local function nextBus()
      i += 1
      if i > #buses then
        polling = false
        choose(results)
        return
      end
      fetch(buses[i], function(t)
        if t and t.title ~= "" then
          table.insert(results, t)
        end
        nextBus()
      end)
    end
    nextBus()
  end
  if lastScan == nil or now() - lastScan >= SCAN_SECONDS then
    scan(readAll)
  else
    readAll()
  end
end

togglePlayback = function()
  if not active then
    return
  end
  noctalia.runAsync({ "busctl", "--user", "call", active, "/org/mpris/MediaPlayer2", "org.mpris.MediaPlayer2.Player", "PlayPause" }, function()
    poll()
  end, 5000)
end

-- ── lifecycle ────────────────────────────────────────────────────────────────

function update()
  poll()
end

-- marquee: hold the start of the title for a moment, then step a frame at a time
function onFrameTick(deltaMs)
  if head.frames <= 1 then
    return
  end
  frameClock += tonumber(deltaMs) or 16
  local wait = if frameIndex == 0 then MARQUEE_HOLD_MS else MARQUEE_FRAME_MS
  if frameClock < wait then
    return
  end
  frameClock = 0
  frameIndex = (frameIndex + 1) % head.frames
  show()
end

if dataDir then
  -- rsvg-convert only sees fontconfig fonts, so point it at the bundled Anton too
  noctalia.writeFile(fontsConf, table.concat({
    '<?xml version="1.0"?>',
    '<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">',
    "<fontconfig>",
    '  <include ignore_missing="yes">/etc/fonts/fonts.conf</include>',
    `  <dir>{pluginDir}/assets</dir>`,
    `  <cachedir>{dataDir}/fccache</cachedir>`,
    "</fontconfig>",
  }, "\n"))
  -- drop renders left over from a previous run
  for _, name in noctalia.listDir(dataDir) or {} do
    if string.match(name, "^title%-%d+%-%d+%.png$") or string.match(name, "^head%-%d+%.png$")
      or string.match(name, "^bottom%-%d+%.png$") or string.match(name, "^player%-%d+%.png$")
      or string.match(name, "^art%-%d+$") then
      noctalia.removeFile(`{dataDir}/{name}`)
    end
  end
end

if not hasTools then
  noctalia.log("phan_site player: needs rsvg-convert (librsvg) and magick (imagemagick)")
end
desktopWidget.render(ui.column({}, {}))
poll()
