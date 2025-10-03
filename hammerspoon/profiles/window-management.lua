-- ICON: 1:
-- NAME: Window Manager
-- DESCRIPTION: Advanced window tiling and management
-- AUTHOR: isaaclins
-- AUTHOR_URL: https://github.com/isaaclins
-- Window management
local cycleIndex = 1

-- Get the usable screen frame (accounts for menu bar, dock, etc.)
local function getUsableFrame(screen)
    return screen:frame() -- Use full frame for all positioning
end

local cornerPositions = {
    -- top-left
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x, y = f.y, w = f.w / 2, h = f.h / 2 }
    end,
    -- top
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x, y = f.y, w = f.w, h = f.h / 2 }
    end,
    -- top-right
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x + f.w / 2, y = f.y, w = f.w / 2, h = f.h / 2 }
    end,
    -- right
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x + f.w / 2, y = f.y, w = f.w / 2, h = f.h }
    end,
    -- bottom-right
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x + f.w / 2, y = f.y + f.h / 2, w = f.w / 2, h = f.h / 2 }
    end,
    -- bottom
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x, y = f.y + f.h / 2, w = f.w, h = f.h / 2 }
    end,
    -- bottom-left
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x, y = f.y + f.h / 2, w = f.w / 2, h = f.h / 2 }
    end,
    -- left
    function(screen)
        local f = getUsableFrame(screen)
        return { x = f.x, y = f.y, w = f.w / 2, h = f.h }
    end
}

-- Helper to check if app is Zen browser (needs special handling)
local function isZenBrowser(win)
    return win:application():name() == "Zen"
end

-- Cooldown to prevent commands from overlapping (Zen needs time to process)
-- Note: Zen browser has positioning bugs - commands need proper spacing
local lastCommandTime = 0
local commandCooldown = 0.3 -- seconds - increased because Zen is slow

-- Use AppleScript for Zen browser (it's buggy with normal methods)
local function moveZenWithAppleScript(bounds)
    -- Round all values to integers for AppleScript
    local x = math.floor(bounds.x + 0.5)
    local y = math.floor(bounds.y + 0.5)
    local w = math.floor(bounds.w + 0.5)
    local h = math.floor(bounds.h + 0.5)

    local script = string.format([[
        tell application "System Events"
            tell process "Zen"
                set frontmost to true
                set position of window 1 to {%d, %d}
                set size of window 1 to {%d, %d}
            end tell
        end tell
    ]], x, y, w, h)

    hs.osascript.applescript(script)
end

local function moveWindow(direction)
    local win = hs.window.focusedWindow()
    if not win then return end

    -- For Zen browser, enforce cooldown to prevent overlapping commands
    if isZenBrowser(win) then
        local now = hs.timer.secondsSinceEpoch()
        local timeSinceLastCommand = now - lastCommandTime
        if timeSinceLastCommand < commandCooldown then
            print("Zen: Command ignored - too soon after previous command (wait " ..
            string.format("%.2f", commandCooldown - timeSinceLastCommand) .. "s)")
            return
        end
        lastCommandTime = now
    end

    local screen = win:screen()
    local f = getUsableFrame(screen)

    -- Debug: print what we're trying to do
    local appName = win:application():name()
    local useAppleScript = isZenBrowser(win)

    if direction == "left" then
        -- Left half
        local newFrame = { x = f.x, y = f.y, w = f.w / 2, h = f.h }
        print(string.format("%s: Moving left to x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, newFrame.x, newFrame.y,
            newFrame.w, newFrame.h))

        if useAppleScript then
            moveZenWithAppleScript(newFrame)
            hs.timer.doAfter(0.1, function()
                local actual = win:frame()
                print(string.format("%s: AppleScript result - at x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, actual.x,
                    actual.y, actual.w, actual.h))
            end)
        else
            win:setFrame(newFrame, 0)
            local actual = win:frame()
            print(string.format("%s: Actually moved to x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, actual.x, actual.y,
                actual.w, actual.h))
        end
    elseif direction == "right" then
        -- Right half
        local newFrame = { x = f.x + f.w / 2, y = f.y, w = f.w / 2, h = f.h }
        print(string.format("%s: Moving right to x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, newFrame.x, newFrame.y,
            newFrame.w, newFrame.h))

        if useAppleScript then
            moveZenWithAppleScript(newFrame)
            hs.timer.doAfter(0.1, function()
                local actual = win:frame()
                print(string.format("%s: AppleScript result - at x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, actual.x,
                    actual.y, actual.w, actual.h))
            end)
        else
            win:setFrame(newFrame, 0)
        end
    elseif direction == "up" then
        if win:isMinimized() then
            win:unminimize()
            hs.timer.doAfter(0.1, function() win:focus() end)
        else
            -- Maximize (fill full screen)
            local newFrame = { x = f.x, y = f.y, w = f.w, h = f.h }
            print(string.format("%s: Maximizing to x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, newFrame.x, newFrame.y,
                newFrame.w, newFrame.h))

            if useAppleScript then
                moveZenWithAppleScript(newFrame)
                hs.timer.doAfter(0.1, function()
                    local actual = win:frame()
                    print(string.format("%s: AppleScript result - at x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, actual.x,
                        actual.y, actual.w, actual.h))
                end)
            else
                win:maximize(0)
            end
        end
    elseif direction == "down" then
        local getFrame = cornerPositions[cycleIndex]
        local newFrame = getFrame(screen)
        print(string.format("%s: Cycling to position %d: x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, cycleIndex, newFrame
        .x, newFrame.y, newFrame.w, newFrame.h))

        if useAppleScript then
            moveZenWithAppleScript(newFrame)
            hs.timer.doAfter(0.1, function()
                local actual = win:frame()
                print(string.format("%s: AppleScript result - at x=%.0f, y=%.0f, w=%.0f, h=%.0f", appName, actual.x,
                    actual.y, actual.w, actual.h))
            end)
        else
            win:setFrame(newFrame, 0)
        end

        cycleIndex = (cycleIndex % #cornerPositions) + 1
    end
end

-- Bind hotkeys
hs.hotkey.bind({ "cmd" }, "left", function() moveWindow("left") end)
hs.hotkey.bind({ "cmd" }, "right", function() moveWindow("right") end)
hs.hotkey.bind({ "cmd" }, "up", function() moveWindow("up") end)
hs.hotkey.bind({ "cmd" }, "down", function() moveWindow("down") end)

hs.alert.show("Hammerspoon config loaded")


