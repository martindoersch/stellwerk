-- Stellwerk ↔ Lightroom Classic
--
-- Lightroom-Plug-ins können nur lauschen, nicht selbst verbinden. Deshalb öffnet das Plug-in zwei Ports
-- auf 127.0.0.1 (vom System vergeben) und schreibt sie nach
--   ~/Library/Application Support/Stellwerk/lightroom-ports   („Empfangsport|Sendeport“)
-- Stellwerk liest die Datei und verbindet sich mit beiden.
--
-- Befehle (Stellwerk → Lightroom, eine Zeile je Befehl):
--   change <Regler> <Delta>     z. B. „change Exposure2012 0.05“ (mehrere Deltas werden zusammengefasst)
--   set <Regler> <Wert>
--   reset <Regler>
--   get <Regler>
--   watch <Regler,Regler,…>     diese Werte melden, auch wenn sie in Lightroom selbst geändert werden
--   do <Aktion>                 next, previous, undo, redo, rating0 … rating5, pick, reject, unflag,
--                               red, yellow, green, blue, purple (Farbmarkierung umschalten), develop, library
--   ping
-- Meldungen (Lightroom → Stellwerk):
--   hello <Version> · value <Regler> <Wert> · module <Name> · photo · error <Text>
--
-- Alle Befehle laufen nacheinander durch eine einzige Schleife: so überholen sich Deltas nicht
-- (Wert lesen + Delta + setzen darf nicht parallel laufen).

local state = require 'State'
state.initRan = true   -- für den Menüpunkt „Stellwerk-Status“

-- Protokoll: ~/Library/Logs/Adobe/Lightroom/LrClassicLogs/Stellwerk.log (ältere Versionen: ~/Documents/LrClassicLogs)
local log = import 'LrLogger'('Stellwerk')
log:enable('logfile')

-- Zusätzliche Spur in /tmp/stellwerk-lightroom.log (das Lightroom-Protokoll erschien beim ersten Test nicht)
local function trace(text)
    log:info(text)
    local f = io.open('/tmp/stellwerk-lightroom.log', 'a')
    if f then f:write(os.date('%H:%M:%S  ') .. text .. '\n'); f:close() end
end
trace('Init.lua startet')

local LrApplication = import 'LrApplication'
local LrApplicationView = import 'LrApplicationView'
local LrDate = import 'LrDate'
local LrDevelopController = import 'LrDevelopController'
local LrFileUtils = import 'LrFileUtils'
local LrFunctionContext = import 'LrFunctionContext'
local LrPathUtils = import 'LrPathUtils'
local LrSelection = import 'LrSelection'
local LrSocket = import 'LrSocket'
local LrTasks = import 'LrTasks'

-- Nicht in jeder Lightroom-Version vorhanden → ein fehlender Namensraum darf das Plug-in nicht stoppen
local hasUndo, LrUndo = pcall(import, 'LrUndo')
if not hasUndo then log:warn('LrUndo fehlt: ' .. tostring(LrUndo)); LrUndo = nil end

local VERSION = '0.1'
-- Startzeit dieser Fassung: „Zusatzmodul neu laden“ startet eine neue, ohne die alte Schleife zu beenden.
-- Die Startzeit steht mit in der Portdatei; findet eine Fassung dort eine neuere, beendet sie sich.
local INSTANCE = string.format('%.3f', LrDate.currentTime())
trace('Stellwerk-Plug-in ' .. VERSION .. ' lädt')

-- MARK: Portdatei

local ports = state.ports

local function portFile()
    -- Fest aus dem Benutzerordner: 'appData' ist in Lightroom womöglich dessen eigener Ordner
    local dir = LrPathUtils.child(LrPathUtils.child(LrPathUtils.getStandardFilePath('home'), 'Library/Application Support'), 'Stellwerk')
    if not LrFileUtils.exists(dir) then LrFileUtils.createAllDirectories(dir) end
    return LrPathUtils.child(dir, 'lightroom-ports')
end

local function writePorts()
    if not (ports.receive and ports.send) then return end
    local path = portFile()
    local f, err = io.open(path, 'w')
    if f then
        f:write(ports.receive .. '|' .. ports.send .. '|' .. INSTANCE)
        f:close()
        state.portFile = path
        trace('Ports ' .. ports.receive .. '|' .. ports.send .. ' → ' .. path)
    else
        state.lastError = 'Portdatei nicht schreibbar: ' .. tostring(err)
        trace(state.lastError)
    end
end

--- Hat eine neuere Fassung des Plug-ins die Portdatei übernommen?
local function newerInstance()
    local f = io.open(portFile(), 'r')
    if not f then return false end
    local text = f:read('*a') or ''
    f:close()
    local other = string.match(text, '^%d+|%d+|([%d%.]+)')
    return other ~= nil and tonumber(other) > tonumber(INSTANCE)
end

-- MARK: Senden

local function send(line)
    if state.sender and state.senderConnected then
        state.sender:send(line .. '\n')
    end
end

local function sendValue(param)
    local ok, v = pcall(LrDevelopController.getValue, param)
    if ok and type(v) == 'number' then
        state.lastValues[param] = v
        send('value ' .. param .. ' ' .. v)
    end
end

-- MARK: Befehle

local function ensureDevelop()
    if LrApplicationView.getCurrentModuleName() ~= 'develop' then
        LrApplicationView.switchToModule('develop')
    end
end

local function clamp(param, v)
    local ok, min, max = pcall(LrDevelopController.getRange, param)
    if ok and min and max then
        if v < min then return min end
        if v > max then return max end
    end
    return v
end

local actions = {
    next = function() LrSelection.nextPhoto() end,
    previous = function() LrSelection.previousPhoto() end,
    undo = function() if LrUndo then LrUndo.undo() end end,
    redo = function() if LrUndo then LrUndo.redo() end end,
    pick = function() LrSelection.flagAsPick() end,
    reject = function() LrSelection.flagAsReject() end,
    unflag = function() LrSelection.removeFlag() end,
    red = function() LrSelection.toggleRedLabel() end,
    yellow = function() LrSelection.toggleYellowLabel() end,
    green = function() LrSelection.toggleGreenLabel() end,
    blue = function() LrSelection.toggleBlueLabel() end,
    purple = function() LrSelection.togglePurpleLabel() end,
    develop = function() LrApplicationView.switchToModule('develop') end,
    library = function() LrApplicationView.switchToModule('library') end,
}
for n = 0, 5 do actions['rating' .. n] = function() LrSelection.setRating(n) end end

local function run(cmd, a, b)
    if cmd == 'change' then
        -- Deltas wurden schon zusammengefasst (siehe drain)
        ensureDevelop()
        local v = (LrDevelopController.getValue(a) or 0) + b
        LrDevelopController.setValue(a, clamp(a, v))
        sendValue(a)
    elseif cmd == 'set' then
        ensureDevelop()
        LrDevelopController.setValue(a, clamp(a, tonumber(b) or 0))
        sendValue(a)
    elseif cmd == 'reset' then
        ensureDevelop()
        LrDevelopController.resetToDefault(a)
        sendValue(a)
    elseif cmd == 'get' then
        sendValue(a)
    elseif cmd == 'watch' then
        state.watched = {}
        state.lastValues = {}
        for p in string.gmatch(a or '', '[^,]+') do state.watched[#state.watched + 1] = p end
        for _, p in ipairs(state.watched) do sendValue(p) end
    elseif cmd == 'do' then
        local f = actions[a]
        if f then f() else send('error unbekannte Aktion ' .. tostring(a)) end
    elseif cmd == 'ping' then
        send('pong')
    else
        send('error unbekannter Befehl ' .. tostring(cmd))
    end
end

--- Alle wartenden Befehle abarbeiten; aufeinanderfolgende „change“ desselben Reglers zusammenfassen
local function drain()
    local q = state.queue
    state.queue = {}
    local i = 1
    while i <= #q do
        local cmd, a, b = q[i][1], q[i][2], q[i][3]
        if cmd == 'change' then
            local sum = tonumber(b) or 0
            while q[i + 1] and q[i + 1][1] == 'change' and q[i + 1][2] == a do
                i = i + 1
                sum = sum + (tonumber(q[i][3]) or 0)
            end
            b = sum
        end
        local ok, err = LrTasks.pcall(run, cmd, a, b)
        if not ok then state.lastError = tostring(err); send('error ' .. tostring(err)) end
        i = i + 1
    end
end

-- MARK: Sockets

local function makeSender(context)
    local gen = state.generation
    state.sender = LrSocket.bind {
        functionContext = context,
        plugin = _PLUGIN,
        address = 'localhost',
        port = 0,
        mode = 'send',
        onConnecting = function(_, port)
            if port ~= ports.send then ports.send = port; trace('Sendeport ' .. tostring(port)); writePorts() end
        end,
        onConnected = function()
            trace('Stellwerk verbunden')
            state.senderConnected = true
            send('hello ' .. VERSION)
            send('module ' .. tostring(LrApplicationView.getCurrentModuleName()))
        end,
        onClosed = function()
            if gen == state.generation then state.senderConnected = false end
        end,
        onError = function(socket, err)
            state.senderConnected = false
            -- „timeout“ = 10 s niemand verbunden → weiter lauschen; sonst neu anlegen (Hauptschleife)
            if gen ~= state.generation then return end   -- alter, gerade geschlossener Socket
            if err == 'timeout' then socket:reconnect() else trace('Sendeport: ' .. tostring(err)); state.needReset = true end
        end,
    }
end

local function makeReceiver(context)
    local gen = state.generation
    return LrSocket.bind {
        functionContext = context,
        plugin = _PLUGIN,
        address = 'localhost',
        port = 0,
        mode = 'receive',
        onConnecting = function(_, port)
            if port ~= ports.receive then ports.receive = port; trace('Empfangsport ' .. tostring(port)); writePorts() end
        end,
        onMessage = function(_, message)
            if type(message) ~= 'string' then return end
            for line in string.gmatch(message, '[^\r\n]+') do
                local cmd, a, b = string.match(line, '^(%S+)%s*(%S*)%s*(.*)$')
                if cmd then state.queue[#state.queue + 1] = { cmd, a, b } end
            end
        end,
        onClosed = function()
            -- Neu verbinden direkt hier klappte nicht (Empfangsport lauschte danach nicht mehr) →
            -- die Hauptschleife legt beide Sockets frisch an
            if gen ~= state.generation then return end
            trace('Stellwerk getrennt')
            state.senderConnected = false
            state.needReset = true
        end,
        onError = function(socket, err)
            if gen ~= state.generation then return end
            if err == 'timeout' then socket:reconnect() else trace('Empfangsport: ' .. tostring(err)); state.needReset = true end
        end,
    }
end

-- MARK: Hauptschleife

local function main(context)
    state.running = true
    local lastInstanceCheck = 0
    local replaced = false
    trace('Sockets werden geöffnet')
    local receiver = makeReceiver(context)
    makeSender(context)

    local module = nil
    local photo = nil
    local lastPoll = 0
    local catalog = LrApplication.activeCatalog()

    while state.running do
        if state.needReset then
            state.needReset = false
            state.generation = state.generation + 1
            pcall(function() receiver:close() end)
            if state.sender then pcall(function() state.sender:close() end) end
            ports.receive, ports.send = nil, nil
            state.queue, state.watched, state.lastValues = {}, {}, {}
            receiver = makeReceiver(context)
            makeSender(context)
        end
        if #state.queue > 0 then drain() end

        -- Alle 200 ms: Modul, Bild und beobachtete Werte (auch mit der Maus geänderte) melden
        local now = LrDate.currentTime()
        if now - lastInstanceCheck >= 1 then
            lastInstanceCheck = now
            if newerInstance() then trace('neuere Fassung läuft – diese beendet sich'); replaced = true; break end
        end
        if state.senderConnected and now - lastPoll >= 0.2 then
            lastPoll = now
            local m = LrApplicationView.getCurrentModuleName()
            if m ~= module then module = m; send('module ' .. tostring(m)) end
            local p = catalog:getTargetPhoto()
            local id = p and p.localIdentifier or nil
            if id ~= photo then photo = id; send('photo') end
            if m == 'develop' then
                for _, param in ipairs(state.watched) do
                    local ok, v = pcall(LrDevelopController.getValue, param)
                    if ok and type(v) == 'number' and v ~= state.lastValues[param] then
                        state.lastValues[param] = v
                        send('value ' .. param .. ' ' .. v)
                    end
                end
            end
        end
        LrTasks.sleep(0.01)
    end

    receiver:close()
    if state.sender then state.sender:close() end
    if not replaced then LrFileUtils.delete(portFile()) end   -- sonst gehört sie der neueren Fassung
    trace('beendet')
end

LrTasks.startAsyncTask(function()
    LrFunctionContext.callWithContext('Stellwerk', function(context)
        local ok, err = LrTasks.pcall(main, context)
        if not ok then state.lastError = 'Abbruch: ' .. tostring(err); trace(state.lastError) end
    end)
end)
