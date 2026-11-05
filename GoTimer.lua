--[[
  GoTimer – grandMA3 Plugin (für 2.3.2, Teststatus siehe README)

  Zweck (Theater): Misst die Zeit zwischen zwei Go+ in einer Sequenz und
  schreibt Mittelwert, Range und letzten Durchlauf in die Note der Cue,
  die durch das Go+ ausgelöst wurde. So sieht man in der Sequenz-Ansicht
  bei der "Next"-Cue, wie lange man nach dem letzten Go ungefähr warten muss.

  Aufruf:
    Plugin "GoTimer"                -> Live-Anzeige an/aus (auch beim Antippen im Plugin-Pool)
    Plugin "GoTimer" "go"           -> Go+ auf der selektierten Sequenz + Messung (für das Go-Makro)
    Plugin "GoTimer" "go 5"         -> Go+ auf Sequenz 5 + Messung
    Plugin "GoTimer" "break"        -> Referenz verwerfen (Pause/Unterbrechung)
    Plugin "GoTimer" "rec"          -> Aufnahme an/aus umschalten
    Plugin "GoTimer" "rec on|off"   -> Aufnahme explizit setzen
    Plugin "GoTimer" "reset"        -> alle Messwerte der selektierten Sequenz löschen
    Plugin "GoTimer" "reset 5"      -> dito für Sequenz 5
    Plugin "GoTimer" "timer 1"      -> Timer 1 aus dem Timer-Pool steuern ("timer on|off", Standard: aus)
    Plugin "GoTimer" "tmode auto"   -> auto|countdown|stopwatch
    Plugin "GoTimer" "gui"          -> Einstellungs-Dialog (Aufnahme, Timer, Statistik, Break, Reset)
    Plugin "GoTimer" "display"      -> Live-Anzeige an/aus ("display on|off")

  Datenhaltung:
    Primär UserVars:  GT_S<seq>_C<cueNo>  =  "n;sum;min;max;last"  (Sekunden)
    Fallback:         Marker-Block in der Cue-Note "[GT 0:41 (0:38-0:45) L0:42 n4]"
                      (wird gelesen, wenn die UserVar fehlt, z.B. anderer User)
]]

local pluginName    = select(1, ...)
local componentName = select(2, ...)
local signalTable   = select(3, ...)
local myHandle      = select(4, ...)

-- ===================== Konfiguration =====================
local CFG = {
  MAX_GAP_SEC   = 15 * 60, -- Abstände darüber gelten als Pause -> nicht werten
  MIN_GAP_SEC   = 0.3,     -- Doppel-Tipper ignorieren
  MARKER_FRONT  = true,    -- Marker vorne in die Note (sonst hinten)
  SETTLE_SEC    = 0.05,    -- kurz warten, bis MA den Cue-Wechsel übernommen hat
  VAR_PREFIX    = "GT_",
  VERBOSE       = true,    -- Meldungen im Command-Line-Feedback
  GO_MACRO_NAME = "GoTimer Go",
  TIMER_ALERT   = "None",  -- Countdown-Alert bei 0:00, wenn in der GUI "Popup" AUS ist

  -- Live-Anzeige. Farben: Name aus ColorGroups.Global oder "Gruppe.Name"
  -- (Liste am Pult: List Root().ColorTheme.ColorGroups.Global.*)
  DISPLAY_NAME         = "GoTimerDisplay",
  DISPLAY_WIDTH        = 560,
  DISPLAY_TICK_SEC     = 0.2,
  DISPLAY_COLOR_NORMAL = "Transparent",
  DISPLAY_COLOR_WINDOW = "Button.BackgroundPlease", -- Zeit liegt in der gemessenen Range
  DISPLAY_COLOR_OVER   = "PartlySelected", -- Zeit liegt über dem bisherigen Maximum
}

-- Laufzeit-Zustand pro Sequenz (lebt, solange das Plugin geladen ist)
-- state[seqNo] = { t = Zeitstempel, idx = Index der Ziel-Cue }
local state = {}

-- ===================== Hilfsfunktionen =====================
local function log(fmt, ...)
  if CFG.VERBOSE then Printf("[GoTimer] " .. fmt, ...) end
end

local function err(fmt, ...)
  ErrPrintf("[GoTimer] " .. fmt, ...)
end

local function now()
  -- Time(): Sekunden seit Programmstart (float). Fallback: os.time() (1s Auflösung)
  if type(Time) == "function" then
    local ok, t = pcall(Time)
    if ok and type(t) == "number" then return t end
  end
  return os.time()
end

local function fmtTime(sec)
  if not sec then return "-" end
  sec = math.floor(sec + 0.5)
  return string.format("%d:%02d", sec // 60, sec % 60)
end

local function parseTime(s)
  local m, ss = s:match("^(%d+):(%d%d)$")
  if not m then return nil end
  return tonumber(m) * 60 + tonumber(ss)
end

local function getProp(obj, name)
  local ok, v = pcall(function() return obj[name] end)
  if ok and v ~= nil then return v end
  ok, v = pcall(function() return obj:Get(name) end)
  if ok then return v end
  return nil
end

local function setProp(obj, name, value)
  local ok = pcall(function() obj[name] = value end)
  if ok then return true end
  ok = pcall(function() obj:Set(name, value) end)
  return ok
end

local function recEnabled()
  local v = GetVar(UserVars(), CFG.VAR_PREFIX .. "REC")
  return v == nil or tostring(v) ~= "0"
end

local function setRec(on)
  SetVar(UserVars(), CFG.VAR_PREFIX .. "REC", on and "1" or "0")
  Printf("[GoTimer] Aufnahme %s", on and "AN" or "AUS")
end

-- Einstellungen, die über die GUI geändert werden können (UserVars, Fallback CFG)
local function maxGapSec()
  local v = tonumber(GetVar(UserVars(), CFG.VAR_PREFIX .. "MAXGAP") or "")
  if v and v > 0 then return v * 60 end
  return CFG.MAX_GAP_SEC
end

local function alertType()
  -- GT_POPUP = "1": Alert am Timer unverändert lassen (Popup erlaubt)
  if tostring(GetVar(UserVars(), CFG.VAR_PREFIX .. "POPUP") or "0") == "1" then return nil end
  return CFG.TIMER_ALERT
end

-- ===================== Sequenz / Cues =====================
local function resolveSequence(arg)
  local no = tonumber(arg or "")
  if no then
    local seq = DataPool().Sequences[no]
    if not seq then err("Sequenz %d existiert nicht", no) end
    return seq
  end
  local seq = SelectedSequence()
  if not seq then err("Keine Sequenz selektiert") end
  return seq
end

local function isRealCue(obj)
  if not obj then return false end
  local ok, cls = pcall(function() return obj:GetClass() end)
  if ok and cls ~= "Cue" then return false end
  local no = getProp(obj, "no")
  return no ~= nil and tonumber(no) ~= 0 -- OffCue / Cue 0 ausschließen
end

local function cueIndex(cue)
  local ok, i = pcall(function() return cue:Index() end)
  if ok and i then return i end
  return getProp(cue, "index")
end

local function currentCue(seq)
  local ok, c = pcall(function() return seq:CurrentChild() end)
  if ok and isRealCue(c) then return c end
  return nil
end

local function nextCueAfter(seq, cue)
  if not cue then return nil end
  local idx = cueIndex(cue)
  local best, bestIdx
  for _, c in ipairs(seq:Children()) do
    if isRealCue(c) then
      local i = cueIndex(c)
      if i and i > idx and (not bestIdx or i < bestIdx) then best, bestIdx = c, i end
    end
  end
  return best
end

local function cueLabel(cue)
  local name = getProp(cue, "name") or "?"
  return tostring(name)
end

-- ===================== Statistik-Speicher =====================
local function varKey(seq, cue)
  local cueNo = tostring(getProp(cue, "no")):gsub("%.", "p")
  return string.format("%sS%s_C%s", CFG.VAR_PREFIX, tostring(seq.no), cueNo)
end

local MARKER_PATTERN = "%[GT [^%]]*%]"

local function statsFromNote(cue)
  local note = tostring(getProp(cue, "note") or "")
  local avg, mn, mx, last, n =
    note:match("%[GT (%d+:%d%d) %((%d+:%d%d)%-(%d+:%d%d)%) L(%d+:%d%d) n(%d+)%]")
  if not avg then return nil end
  n = tonumber(n)
  return {
    n = n, sum = parseTime(avg) * n,
    min = parseTime(mn), max = parseTime(mx), last = parseTime(last),
  }
end

local function loadStats(seq, cue)
  local raw = GetVar(UserVars(), varKey(seq, cue))
  if raw then
    local n, sum, mn, mx, last = tostring(raw):match("^([^;]+);([^;]+);([^;]+);([^;]+);([^;]+)$")
    if n then
      return { n = tonumber(n), sum = tonumber(sum), min = tonumber(mn),
               max = tonumber(mx), last = tonumber(last) }
    end
  end
  return statsFromNote(cue) -- Fallback
end

local function saveStats(seq, cue, s)
  SetVar(UserVars(), varKey(seq, cue),
    string.format("%d;%.2f;%.2f;%.2f;%.2f", s.n, s.sum, s.min, s.max, s.last))
end

local function markerText(s)
  return string.format("[GT %s (%s-%s) L%s n%d]",
    fmtTime(s.sum / s.n), fmtTime(s.min), fmtTime(s.max), fmtTime(s.last), s.n)
end

local function stripMarker(note)
  note = note:gsub("%s*" .. MARKER_PATTERN .. "%s*", " ")
  return (note:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function writeNote(cue, s)
  local userText = stripMarker(tostring(getProp(cue, "note") or ""))
  local marker = markerText(s)
  local newNote
  if userText == "" then
    newNote = marker
  elseif CFG.MARKER_FRONT then
    newNote = marker .. " " .. userText
  else
    newNote = userText .. " " .. marker
  end
  if not setProp(cue, "note", newNote) then
    err("Konnte Note nicht schreiben (Cue %s)", cueLabel(cue))
  end
end

local function record(seq, cue, delta)
  local s = loadStats(seq, cue) or { n = 0, sum = 0 }
  s.n    = s.n + 1
  s.sum  = s.sum + delta
  s.min  = s.min and math.min(s.min, delta) or delta
  s.max  = s.max and math.max(s.max, delta) or delta
  s.last = delta
  saveStats(seq, cue, s)
  writeNote(cue, s)
  log("Seq %s Cue '%s': %s  %s", tostring(seq.no), cueLabel(cue), fmtTime(delta), markerText(s))
end

-- ===================== Live-Timer (Timer-Pool / Clock-Fenster) =====================
-- Settings in UserVars: GT_TIMER_ON = 1 (Standard: aus), GT_TIMER = Timer-Nummer,
-- GT_TMODE = auto|countdown|stopwatch
local function timerNumber()
  local v = tonumber(GetVar(UserVars(), CFG.VAR_PREFIX .. "TIMER") or "")
  if v and v > 0 then return v end
  return 1
end

local function timerEnabled()
  return tostring(GetVar(UserVars(), CFG.VAR_PREFIX .. "TIMER_ON") or "0") == "1"
end

local function setTimerEnabled(on)
  SetVar(UserVars(), CFG.VAR_PREFIX .. "TIMER_ON", on and "1" or "0")
end

-- Nummer des zu steuernden Timers oder nil, wenn der Timer deaktiviert ist
local function timerNo()
  if timerEnabled() then return timerNumber() end
  return nil
end

local function timerMode()
  local v = GetVar(UserVars(), CFG.VAR_PREFIX .. "TMODE")
  return v and tostring(v) or "auto"
end

local function triggerType(cue)
  for _, p in ipairs({ "trigtype", "trig", "trigger" }) do
    local v = getProp(cue, p)
    if v ~= nil then return tostring(v):lower() end
  end
  return nil
end

-- Cue, die das nächste manuelle Go+ auslösen wird (Follow-/Time-Cues werden übersprungen)
local function nextGoCue(seq, cue)
  local c = nextCueAfter(seq, cue)
  local guard = 0
  while c and guard < 50 do
    local trig = triggerType(c)
    if not trig or trig == "" or trig:find("go") then return c end
    c = nextCueAfter(seq, c)
    guard = guard + 1
  end
  return nil
end

local function restartTimer(seq, landedCue)
  local no = timerNo()
  if not no then return end

  local nextCue = landedCue and nextGoCue(seq, landedCue)
  local s = nextCue and loadStats(seq, nextCue)
  local mode = timerMode()
  local useCountdown = (mode == "countdown" or mode == "auto") and s ~= nil

  local label
  if nextCue and s then
    label = string.format("%s ~%s (%s-%s)", cueLabel(nextCue),
      fmtTime(s.sum / s.n), fmtTime(s.min), fmtTime(s.max))
  elseif nextCue then
    label = cueLabel(nextCue) .. " (keine Daten)"
  else
    label = "Ende"
  end
  label = label:gsub('"', "'")

  Cmd(string.format('Off Timer %d', no))
  if useCountdown then
    Cmd(string.format('Set Timer %d "TimerMode" "Countdown"', no))
    Cmd(string.format('Set Timer %d "CountdownDuration" %.1f', no, s.sum / s.n))
    local alert = alertType()
    if alert then
      Cmd(string.format('Set Timer %d "CountdownAlertType" "%s"', no, alert))
    end
  else
    Cmd(string.format('Set Timer %d "TimerMode" "Stopwatch"', no))
  end
  Cmd(string.format('Set Timer %d "Name" "%s"', no, label))
  Cmd(string.format('Go Timer %d', no))
end

local function stopTimer()
  local no = timerNo()
  if no then Cmd(string.format('Off Timer %d', no)) end
end

-- ===================== Live-Anzeige (Lua-Overlay) =====================
-- Liest nur den Zustand in `live`. Das Go läuft unabhängig davon, die Anzeige
-- schreibt nichts in die Show. Kein Signal-Handler: der CloseButton schließt selbst.
local live = { t = nil, nextName = nil, stats = nil, atEnd = false }

local function setLive(seq, t, landedCue)
  local nextCue = landedCue and nextGoCue(seq, landedCue)
  live.t        = t
  live.nextName = nextCue and cueLabel(nextCue) or nil
  live.stats    = nextCue and loadStats(seq, nextCue) or nil
  live.atEnd    = landedCue ~= nil and nextCue == nil
end

local function clearLive()
  live.t, live.nextName, live.stats, live.atEnd = nil, nil, nil, false
end

-- Vergleichszeit oben in der Anzeige: GT_DISP_REF = avg (Standard) | last
local function displayRef()
  return tostring(GetVar(UserVars(), CFG.VAR_PREFIX .. "DISP_REF") or "avg")
end

-- Liefert Zeit-Text, Info-Text und Farbname für den aktuellen Zustand
local function displayContent(tNow)
  local s = live.stats
  local info
  if live.atEnd then
    info = "Ende der Sequenz"
  elseif live.nextName and s then
    info = string.format("Next: %s  (%s-%s)", live.nextName, fmtTime(s.min), fmtTime(s.max))
  elseif live.nextName then
    info = string.format("Next: %s  (keine Daten)", live.nextName)
  else
    info = "Warte auf Go"
  end

  if not live.t then return "-:--", info, CFG.DISPLAY_COLOR_NORMAL end

  local elapsed = math.floor(tNow - live.t)
  if not s then return fmtTime(elapsed), info, CFG.DISPLAY_COLOR_NORMAL end

  local useLast = displayRef() == "last"
  local ref = useLast and s.last or (s.sum / s.n)
  local text = string.format("%s / %s%s", fmtTime(elapsed), useLast and "L" or "~", fmtTime(ref))
  local over = elapsed - math.floor(ref + 0.5)
  if over >= 1 then text = string.format("%s  (+%s)", text, fmtTime(over)) end

  local color = CFG.DISPLAY_COLOR_NORMAL
  if elapsed > s.max then
    color = CFG.DISPLAY_COLOR_OVER
  elseif elapsed >= s.min then
    color = CFG.DISPLAY_COLOR_WINDOW
  end
  return text, info, color
end

local function uiSet(obj, prop, value)
  local ok, e = pcall(function() obj[prop] = value end)
  if not ok then log("Property %s nicht gesetzt: %s", prop, tostring(e)) end
end

local function uiValid(h)
  if h == nil then return false end
  if type(IsObjectValid) == "function" then
    local ok, v = pcall(IsObjectValid, h)
    if ok then return v and true or false end
  end
  return true
end

local function removeWindow(overlay, win)
  if overlay and uiValid(win) then
    local ok, e = pcall(function() Obj.Delete(overlay, Obj.Index(win)) end)
    if not ok then log("Anzeige nicht entfernt: %s", tostring(e)) end
  end
end

local function themeColor(name)
  local group, color = name:match("^([^.]+)%.(.+)$")
  if not group then group, color = "Global", name end
  local ok, c = pcall(function() return Root().ColorTheme.ColorGroups[group][color] end)
  return ok and c or nil
end

-- Ruft das Plugin selbst in einem eigenen Durchlauf auf
local function selfCommand(argument)
  CmdIndirect(string.format('Plugin "%s" "%s"', tostring(pluginName or "GoTimer"), argument))
end

-- Klick auf "Config" in der Anzeige. Bewusst minimal und abgesichert: Fehler im
-- UI-Callback dürfen nicht nach außen dringen, das Menü läuft in einem eigenen Aufruf.
if signalTable then
  signalTable.GoTimerOpenConfig = function(caller)
    local ok, e = pcall(selfCommand, "gui")
    if not ok then err("Config-Menü nicht geöffnet: %s", tostring(e)) end
  end
end

local function addDisplayLabel(parent, anchors)
  local l = parent:Append("UIObject")
  uiSet(l, "Anchors", anchors)
  uiSet(l, "Font", "Medium20")
  uiSet(l, "TextalignmentH", "Centre")
  uiSet(l, "HasHover", "No")
  return l
end

local function buildDisplay(overlay)
  local win = overlay:Append("BaseInput")
  uiSet(win, "Name", CFG.DISPLAY_NAME)
  uiSet(win, "W", CFG.DISPLAY_WIDTH)
  uiSet(win, "H", 0)
  uiSet(win, "Columns", 1)
  uiSet(win, "Rows", 2)
  win[1][1].SizePolicy = "Fixed"
  win[1][1].Size = 60
  win[1][2].SizePolicy = "Stretch"
  uiSet(win, "AutoClose", "No")
  uiSet(win, "CloseOnEscape", "No") -- Esc wird im Betrieb gebraucht und darf die Anzeige nicht schließen

  local title = win:Append("TitleBar")
  uiSet(title, "Columns", 3)
  uiSet(title, "Rows", 1)
  uiSet(title, "Anchors", "0,0")
  title[2][2].SizePolicy = "Fixed"
  title[2][2].Size = 110
  title[2][3].SizePolicy = "Fixed"
  title[2][3].Size = 50

  local caption = title:Append("TitleButton")
  uiSet(caption, "Text", "GoTimer")
  uiSet(caption, "Anchors", "0,0")

  local config = title:Append("Button")
  uiSet(config, "Text", "Config")
  uiSet(config, "Anchors", "1,0")
  uiSet(config, "Font", "Medium20")
  uiSet(config, "TextalignmentH", "Centre")
  uiSet(config, "HasHover", "Yes")
  uiSet(config, "PluginComponent", myHandle)
  uiSet(config, "Clicked", "GoTimerOpenConfig")

  -- CloseButton schließt sich selbst und bekommt absichtlich keinen Handler
  local close = title:Append("CloseButton")
  uiSet(close, "Anchors", "2,0")

  local frame = win:Append("DialogFrame")
  uiSet(frame, "H", "100%")
  uiSet(frame, "W", "100%")
  uiSet(frame, "Columns", 1)
  uiSet(frame, "Rows", 2)
  uiSet(frame, "Anchors", "0,1")
  frame[1][1].SizePolicy = "Fixed"
  frame[1][1].Size = 60
  frame[1][2].SizePolicy = "Fixed"
  frame[1][2].Size = 60

  return win, addDisplayLabel(frame, "0,0"), addDisplayLabel(frame, "0,1")
end

local displayToken = nil

local function runDisplay()
  local token = {}
  displayToken = token -- eine evtl. laufende Anzeige beendet sich beim nächsten Tick
  coroutine.yield(CFG.DISPLAY_TICK_SEC * 2)
  if displayToken ~= token then return end

  local overlay = GetFocusDisplay().ScreenOverlay
  local foundOk, stale = pcall(function() return overlay:FindRecursive(CFG.DISPLAY_NAME, "BaseInput") end)
  if foundOk and stale then removeWindow(overlay, stale) end

  -- Beim Öffnen die nächste Cue zeigen, auch wenn seit dem Start noch kein Go kam
  if not live.t then
    local seq = SelectedSequence()
    local cur = seq and currentCue(seq)
    if cur then setLive(seq, nil, cur) end
  end

  local win, timeLabel, infoLabel = buildDisplay(overlay)
  local colors = {}
  local lastTime, lastInfo, lastColor

  local ok, e = pcall(function()
    while displayToken == token and uiValid(win) and uiValid(timeLabel) and uiValid(infoLabel) do
      local text, info, colorName = displayContent(now())
      if text ~= lastTime then timeLabel.Text = text; lastTime = text end
      if info ~= lastInfo then infoLabel.Text = info; lastInfo = info end
      if colorName ~= lastColor then
        if colors[colorName] == nil then colors[colorName] = themeColor(colorName) or false end
        if colors[colorName] then timeLabel.BackColor = colors[colorName] end
        lastColor = colorName
      end
      coroutine.yield(CFG.DISPLAY_TICK_SEC)
    end
  end)
  if not ok then err("Anzeige beendet: %s", tostring(e)) end

  removeWindow(overlay, win)
  if displayToken == token then displayToken = nil end
end

-- ===================== Aktionen =====================
local function doGo(seq)
  local seqNo  = seq.no
  local before = currentCue(seq)
  local target = nextCueAfter(seq, before) -- Ziel vor dem Go bestimmen (robust gegen schnelle Follows)
  local t      = now()

  Cmd("Go+ Sequence " .. tostring(seqNo))
  coroutine.yield(CFG.SETTLE_SEC)

  local after = currentCue(seq)
  if not after then state[seqNo] = nil; clearLive(); stopTimer(); return end

  -- Anzeige und Timer sofort aktualisieren (auch wenn Aufnahme AUS ist – also in der Vorstellung)
  setLive(seq, t, after)
  restartTimer(seq, after)

  if before and not target then
    -- Go+ auf der letzten Cue (Wrap oder Ende): nichts werten
    state[seqNo] = { t = t, idx = cueIndex(after) }
    log("Ende der Sequenz/Wrap – Referenz neu gesetzt")
    return
  end
  -- Sequenz war aus: die tatsächlich erreichte Cue ist das Ziel
  if not target then target = after end

  local afterIdx, targetIdx = cueIndex(after), cueIndex(target)
  if afterIdx < targetIdx then
    -- Rückwärts / Wrap: als neuen Startpunkt nehmen, nichts werten
    state[seqNo] = { t = t, idx = afterIdx }
    log("Wrap/Rücksprung erkannt – Referenz neu gesetzt")
    return
  end

  local prev = state[seqNo]
  state[seqNo] = { t = t, idx = targetIdx }

  if not recEnabled() then return end
  if not prev or not before then
    log("Startpunkt gesetzt (Cue '%s')", cueLabel(target))
    return
  end

  -- Plausibilität: Seit dem letzten Go darf es nur vorwärts gegangen sein (Follows ok)
  if cueIndex(before) < prev.idx then
    log("Sprung zurück seit letztem Go – nicht gewertet")
    return
  end

  local delta = t - prev.t
  if delta < CFG.MIN_GAP_SEC then return end
  if delta > maxGapSec() then
    log("Abstand %s > Limit – als Pause gewertet, nicht gespeichert", fmtTime(delta))
    return
  end

  record(seq, target, delta)
end

local function doReset(seq)
  local count = 0
  for _, c in ipairs(seq:Children()) do
    if isRealCue(c) then
      pcall(DelVar, UserVars(), varKey(seq, c))
      local note = tostring(getProp(c, "note") or "")
      if note:find(MARKER_PATTERN) then
        setProp(c, "note", stripMarker(note))
        count = count + 1
      end
    end
  end
  state[seq.no] = nil
  live.stats = nil
  Printf("[GoTimer] Sequenz %s zurückgesetzt (%d Notes bereinigt)", tostring(seq.no), count)
end

-- ===================== GUI (MessageBox) =====================
local BTN = { CLOSE = 0, APPLY = 1, STATS = 2, BREAK = 3, RESET = 4, DISPLAY = 5, MACRO = 6 }
local MODES = { "auto", "countdown", "stopwatch" }
local MODE_VALUE = { auto = 1, countdown = 2, stopwatch = 3 }
local REFS = { "avg", "last" }
local REF_VALUE = { avg = 1, last = 2 }
local STATS_MAX_LINES = 30

local function seqTitle(seq)
  return string.format("Sequenz %s '%s'", tostring(seq.no), tostring(getProp(seq, "name") or ""))
end

local function statsLine(cue, s)
  return string.format("%s:  avg %s   %s-%s   letzt %s   n=%d",
    cueLabel(cue), fmtTime(s.sum / s.n), fmtTime(s.min), fmtTime(s.max), fmtTime(s.last), s.n)
end

local function headerInfo(seq)
  if not seq then return "Keine Sequenz selektiert." end
  local total, withData = 0, 0
  for _, c in ipairs(seq:Children()) do
    if isRealCue(c) then
      total = total + 1
      if loadStats(seq, c) then withData = withData + 1 end
    end
  end
  local lines = {
    seqTitle(seq),
    string.format("%d von %d Cues mit Messwerten", withData, total),
  }
  local cur = currentCue(seq)
  if cur then
    local nxt = nextGoCue(seq, cur)
    local s = nxt and loadStats(seq, nxt)
    lines[#lines + 1] = string.format("Aktuell: %s  ->  nächstes Go: %s", cueLabel(cur),
      nxt and (cueLabel(nxt) .. (s and (" ~" .. fmtTime(s.sum / s.n)) or " (keine Daten)")) or "-")
  else
    lines[#lines + 1] = "Sequenz ist aus."
  end
  return table.concat(lines, "\n")
end

local function showStats(display, seq)
  local lines, count, hidden = {}, 0, 0
  for _, c in ipairs(seq:Children()) do
    if isRealCue(c) then
      local s = loadStats(seq, c)
      if s then
        count = count + 1
        if count <= STATS_MAX_LINES then lines[#lines + 1] = statsLine(c, s) else hidden = hidden + 1 end
      end
    end
  end
  if count == 0 then lines[1] = "Noch keine Messwerte." end
  if hidden > 0 then lines[#lines + 1] = string.format("... und %d weitere", hidden) end
  MessageBox({
    title = "GoTimer – Statistik " .. seqTitle(seq),
    message = table.concat(lines, "\n"),
    display = display,
    commands = { { value = 1, name = "Zurück" } },
  })
end

local function confirm(display, title, message)
  local res = MessageBox({
    title = title, message = message, display = display,
    commands = { { value = 1, name = "Ja" }, { value = 0, name = "Nein" } },
  })
  return res and res.result == 1
end

local function applySettings(res)
  local inputs, states, selectors = res.inputs or {}, res.states or {}, res.selectors or {}

  local rec = states["Aufnahme"]
  if rec ~= nil and rec ~= recEnabled() then setRec(rec) end

  local popup = states["Popup bei 0:00"]
  if popup ~= nil then SetVar(UserVars(), CFG.VAR_PREFIX .. "POPUP", popup and "1" or "0") end

  -- Einen bisher gesteuerten Timer stoppen, wenn er deaktiviert oder gewechselt wird
  local oldTimer = timerNo()
  local tno = tonumber(inputs["Timer-Nr"] or "")
  if tno and tno > 0 then SetVar(UserVars(), CFG.VAR_PREFIX .. "TIMER", tostring(math.floor(tno))) end
  local timerOn = states["Timer"]
  if timerOn ~= nil then setTimerEnabled(timerOn) end
  if oldTimer and oldTimer ~= timerNo() then Cmd(string.format("Off Timer %d", oldTimer)) end

  local gap = tonumber(inputs["Pause ab (Minuten)"] or "")
  if gap and gap > 0 then SetVar(UserVars(), CFG.VAR_PREFIX .. "MAXGAP", tostring(gap)) end

  local m = MODES[selectors["Timer-Modus"] or 0]
  if m then SetVar(UserVars(), CFG.VAR_PREFIX .. "TMODE", m) end

  local ref = REFS[selectors["Zeit in Anzeige"] or 0]
  if ref then SetVar(UserVars(), CFG.VAR_PREFIX .. "DISP_REF", ref) end
end

-- Legt das Go-Makro im ersten freien Macro-Platz an. Vorhandene Makros bleiben unberührt.
-- Rückgabe: Macro-Nummer und true, wenn es neu ist (bei Fehler: nil und Meldung)
local function createGoMacro()
  local macros = DataPool().Macros
  for _, m in ipairs(macros:Children()) do
    if tostring(getProp(m, "name") or "") == CFG.GO_MACRO_NAME then
      return getProp(m, "no"), false
    end
  end

  local no = 1
  while macros[no] ~= nil do no = no + 1 end
  Cmd(string.format("Store Macro %d /NoOops", no))

  local macro = DataPool().Macros[no]
  if not macro then return nil, string.format("Macro %d konnte nicht angelegt werden", no) end
  macro:Set("Name", CFG.GO_MACRO_NAME)
  local line = macro:Insert()
  line:Set("Command", string.format('Plugin "%s" "go"', tostring(pluginName or "GoTimer")))
  return no, true
end

local function showGoMacroResult(display)
  local ok, no, isNew = pcall(createGoMacro)
  local message
  if not ok then
    message = "Makro nicht angelegt:\n" .. tostring(no)
  elseif not no then
    message = "Makro nicht angelegt:\n" .. tostring(isNew)
  elseif isNew then
    message = string.format("Makro %s '%s' angelegt.\nLege es auf einen Executor-Button oder X-Key.",
      tostring(no), CFG.GO_MACRO_NAME)
  else
    message = string.format("Makro %s '%s' gibt es schon.\nEs wurde nicht verändert.",
      tostring(no), CFG.GO_MACRO_NAME)
  end
  MessageBox({
    title = "GoTimer – Go-Makro", message = message, display = display,
    commands = { { value = 1, name = "OK" } },
  })
end

local guiOpen = false

local function openGui(display)
  while true do
    local seq = SelectedSequence()
    local res = MessageBox({
      title = "GoTimer",
      message = headerInfo(seq),
      display = display,
      commands = {
        { value = BTN.APPLY, name = "OK" },
        { value = BTN.DISPLAY, name = "Anzeige" },
        { value = BTN.MACRO, name = "Go-Makro" },
        { value = BTN.STATS, name = "Statistik" },
        { value = BTN.BREAK, name = "Break" },
        { value = BTN.RESET, name = "Reset Sequenz" },
        { value = BTN.CLOSE, name = "Abbrechen" },
      },
      states = {
        { name = "Aufnahme", state = recEnabled() },
        { name = "Timer", state = timerEnabled() },
        { name = "Popup bei 0:00", state = alertType() == nil },
      },
      inputs = {
        { name = "Timer-Nr", value = tostring(timerNumber()),
          whiteFilter = "0123456789", vkPlugin = "NumericInput", maxTextLength = 4 },
        { name = "Pause ab (Minuten)", value = tostring(math.floor(maxGapSec() / 60 + 0.5)),
          whiteFilter = "0123456789", vkPlugin = "NumericInput", maxTextLength = 3 },
      },
      selectors = {
        { name = "Timer-Modus", selectedValue = MODE_VALUE[timerMode()] or 1, type = 1,
          values = { ["Auto"] = 1, ["Countdown"] = 2, ["Stopwatch"] = 3 } },
        { name = "Zeit in Anzeige", selectedValue = REF_VALUE[displayRef()] or 1, type = 1,
          values = { ["Durchschnitt"] = 1, ["Letzter Durchlauf"] = 2 } },
      },
    })

    local btn = res and res.result or BTN.CLOSE
    if btn == BTN.CLOSE then return end
    applySettings(res)

    if btn == BTN.APPLY then
      return
    elseif btn == BTN.DISPLAY then
      -- Eigener Plugin-Aufruf, damit die Anzeige nicht in diesem Dialog weiterläuft
      selfCommand("display")
      return
    elseif btn == BTN.MACRO then
      showGoMacroResult(display)
    elseif not seq then
      err("Keine Sequenz selektiert")
    elseif btn == BTN.STATS then
      showStats(display, seq)
    elseif btn == BTN.BREAK then
      state[seq.no] = nil; clearLive(); stopTimer()
      log("Referenz für Sequenz %s verworfen", tostring(seq.no))
    elseif btn == BTN.RESET then
      if confirm(display, "GoTimer – Reset",
          "Alle Messwerte und [GT]-Marker in\n" .. seqTitle(seq) .. "\nlöschen?") then
        doReset(seq)
      end
    end
  end
end

-- ===================== Einstieg =====================
local function Main(display_handle, argument)
  local args = {}
  for w in tostring(argument or ""):gmatch("%S+") do args[#args + 1] = w end
  local cmd = (args[1] or "display"):lower() -- Antippen im Pool: nie ein Go auslösen

  if cmd == "gui" or cmd == "menu" then
    if guiOpen then return end -- z.B. Doppelklick auf "Config"
    guiOpen = true
    local ok, e = pcall(openGui, display_handle)
    guiOpen = false
    if not ok then err("Menü beendet: %s", tostring(e)) end
  elseif cmd == "go" then
    local seq = resolveSequence(args[2]); if seq then doGo(seq) end
  elseif cmd == "break" then
    local seq = resolveSequence(args[2])
    if seq then state[seq.no] = nil; clearLive(); stopTimer(); log("Referenz für Sequenz %s verworfen", tostring(seq.no)) end
  elseif cmd == "display" then
    local a = (args[2] or ""):lower()
    if a == "off" or (a ~= "on" and displayToken) then
      displayToken = nil
    else
      runDisplay()
    end
  elseif cmd == "timer" then
    local a = (args[2] or ""):lower()
    local n = tonumber(a)
    if n and n > 0 then
      SetVar(UserVars(), CFG.VAR_PREFIX .. "TIMER", tostring(math.floor(n)))
      setTimerEnabled(true)
    elseif a == "on" then
      setTimerEnabled(true)
    else
      stopTimer()
      setTimerEnabled(false)
    end
    Printf("[GoTimer] Live-Timer: %s", timerEnabled() and ("Timer " .. timerNumber()) or "AUS")
  elseif cmd == "tmode" then
    local a = (args[2] or ""):lower()
    if a ~= "auto" and a ~= "countdown" and a ~= "stopwatch" then
      err("tmode erwartet auto|countdown|stopwatch"); return
    end
    SetVar(UserVars(), CFG.VAR_PREFIX .. "TMODE", a)
    Printf("[GoTimer] Timer-Modus: %s", a)
  elseif cmd == "rec" then
    local a = (args[2] or ""):lower()
    if a == "on" then setRec(true) elseif a == "off" then setRec(false) else setRec(not recEnabled()) end
  elseif cmd == "reset" then
    local seq = resolveSequence(args[2]); if seq then doReset(seq) end
  else
    err("Unbekanntes Argument '%s' (go|gui|display|break|rec|reset|timer|tmode)", cmd)
  end
end

return Main
