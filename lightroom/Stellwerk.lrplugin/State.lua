-- Gemeinsamer Zustand für Init.lua, Shutdown.lua und Status.lua (require liefert innerhalb des Plug-ins dieselbe Tabelle)
return {
    initRan = false,
    running = false,
    ports = { receive = nil, send = nil },
    portFile = nil,        -- Pfad, sobald geschrieben
    lastError = nil,
    sender = nil,          -- Socket Lightroom → Stellwerk
    senderConnected = false,
    generation = 1,        -- Sockets einer Generation; Meldungen älterer (geschlossener) zählen nicht
    needReset = false,     -- Stellwerk getrennt → Hauptschleife legt beide Sockets neu an
    queue = {},            -- eingegangene Befehle, abgearbeitet von einer einzigen Schleife
    watched = {},          -- Regler, deren Werte Stellwerk sehen will
    lastValues = {},
}
