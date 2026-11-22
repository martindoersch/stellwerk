-- Beim Deaktivieren des Plug-ins oder Beenden von Lightroom: Schleifen und Sockets beenden.
-- Lightroom erwartet eine Funktion, die doneFunction aufruft – sonst meldet es „reagiert nicht“.
local state = require 'State'

return {
    LrShutdownFunction = function(doneFunction)
        state.running = false
        doneFunction()
    end,
}
