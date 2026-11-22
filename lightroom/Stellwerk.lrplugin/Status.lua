-- Menüpunkt „Stellwerk-Status“ (Datei › Zusatzmoduloptionen bzw. Bibliothek › Zusatzmoduloptionen):
-- zeigt, ob das Plug-in läuft, welche Ports es geöffnet hat und ob Stellwerk verbunden ist.
local LrDialogs = import 'LrDialogs'
local LrTasks = import 'LrTasks'
local state = require 'State'

LrTasks.startAsyncTask(function()
    local lines = {
        'Init.lua gelaufen: ' .. tostring(state.initRan),
        'Schleife läuft: ' .. tostring(state.running),
        'Empfangsport: ' .. tostring(state.ports.receive),
        'Sendeport: ' .. tostring(state.ports.send),
        'Portdatei: ' .. tostring(state.portFile),
        'Stellwerk verbunden: ' .. tostring(state.senderConnected),
        'Letzter Fehler: ' .. tostring(state.lastError),
    }
    LrDialogs.message('Stellwerk-Status', table.concat(lines, '\n'), 'info')
end)
