-- ICON: 2
-- NAME: Recursive Window Tiler
-- DESCRIPTION: Recursive Window Tiler for Hammerspoon
-- AUTHOR: isaaclins
-- AUTHOR_URL: https://github.com/isaaclins
-- Logic: First split is horizontal (left/right)
-- Subsequent windows split the bottom-most, right-most window vertically

local windowManager = {}
windowManager.windows = {}
windowManager.tree = nil

-- Blacklist: Apps to ignore
windowManager.blacklist = {
    "Raycast",
    "Alfred",
    "Spotlight",
    "Notification Center",
    "Control Center",
    "Battery",
    -- Add more apps here as needed
}

-- Path to save blacklist
windowManager.blacklistPath = os.getenv("HOME") .. "/.hammerspoon/blacklist.txt"

-- Load blacklist from file
local function loadBlacklist()
    local file = io.open(windowManager.blacklistPath, "r")
    if file then
        windowManager.blacklist = {}
        for line in file:lines() do
            if line and line ~= "" then
                table.insert(windowManager.blacklist, line)
            end
        end
        file:close()
        return true
    end
    return false
end

-- Save blacklist to file
local function saveBlacklist()
    local file = io.open(windowManager.blacklistPath, "w")
    if file then
        for _, appName in ipairs(windowManager.blacklist) do
            file:write(appName .. "\n")
        end
        file:close()
    end
end

-- Check if an app is blacklisted
local function isBlacklisted(appName)
    for _, name in ipairs(windowManager.blacklist) do
        if appName == name then
            return true
        end
    end
    return false
end

-- Add app to blacklist
local function addToBlacklist(appName)
    if not isBlacklisted(appName) then
        table.insert(windowManager.blacklist, appName)
        saveBlacklist()
        return true
    end
    return false
end

-- Remove app from blacklist
local function removeFromBlacklist(appName)
    for i, name in ipairs(windowManager.blacklist) do
        if name == appName then
            table.remove(windowManager.blacklist, i)
            saveBlacklist()
            return true
        end
    end
    return false
end

-- Toggle blacklist for app
local function toggleBlacklist(appName)
    if isBlacklisted(appName) then
        removeFromBlacklist(appName)
        return false -- Now not blacklisted
    else
        addToBlacklist(appName)
        return true -- Now blacklisted
    end
end

-- Check if a window should be managed
local function shouldManageWindow(window)
    if not window then return false end

    -- Get the app name
    local app = window:application()
    if not app then return false end
    local appName = app:name()

    -- Check blacklist
    if isBlacklisted(appName) then
        return false
    end

    -- Only manage standard windows (not popups, dialogs, etc.)
    if not window:isStandard() then
        return false
    end

    -- Must be visible
    if not window:isVisible() then
        return false
    end

    -- Exclude windows without a title (often system dialogs)
    local title = window:title()
    if not title or title == "" then
        return false
    end

    -- Exclude very small windows (likely popups/alerts)
    local frame = window:frame()
    if frame.w < 200 or frame.h < 100 then
        return false
    end

    return true
end

-- Tree node structure
-- node = { window = hs.window, left = node, right = node, parent = node, bounds = {x, y, w, h} }

-- Get the screen frame
local function getScreenFrame()
    return hs.screen.mainScreen():frame()
end

-- Find the bottom-most, right-most leaf node in the tree
local function findBottomRightLeaf(node)
    if not node then return nil end

    -- If it's a leaf node, return it
    if not node.left and not node.right then
        return node
    end

    -- If it has a right child, traverse right
    if node.right then
        return findBottomRightLeaf(node.right)
    end

    -- Otherwise traverse left
    if node.left then
        return findBottomRightLeaf(node.left)
    end

    return node
end

-- Calculate bounds for all nodes in the tree
local function calculateBounds(node, x, y, w, h, isHorizontalSplit)
    if not node then return end

    -- If it's a leaf node, store the bounds
    if not node.left and not node.right then
        node.bounds = { x = x, y = y, w = w, h = h }
        return
    end

    -- Split the space
    if isHorizontalSplit then
        -- Horizontal split (left/right)
        local leftW = w / 2
        local rightW = w / 2

        if node.left then
            calculateBounds(node.left, x, y, leftW, h, false)
        end
        if node.right then
            calculateBounds(node.right, x + leftW, y, rightW, h, false)
        end
    else
        -- Vertical split (top/bottom)
        local topH = h / 2
        local bottomH = h / 2

        if node.left then
            calculateBounds(node.left, x, y, w, topH, false)
        end
        if node.right then
            calculateBounds(node.right, x, y + topH, w, bottomH, false)
        end
    end
end

-- Apply window layouts based on tree
local function applyLayout()
    if not windowManager.tree then return end

    local screen = getScreenFrame()

    -- Calculate bounds for all nodes
    -- Root is always horizontal split
    calculateBounds(windowManager.tree, screen.x, screen.y, screen.w, screen.h, true)

    -- Apply bounds to windows
    local function applyBoundsToWindows(node)
        if not node then return end

        if node.window and node.bounds then
            local frame = {
                x = node.bounds.x,
                y = node.bounds.y,
                w = node.bounds.w,
                h = node.bounds.h
            }
            node.window:setFrame(frame, 0)
        end

        applyBoundsToWindows(node.left)
        applyBoundsToWindows(node.right)
    end

    applyBoundsToWindows(windowManager.tree)
end

-- Add a window to the tree
local function addWindow(window)
    if not window then return end

    -- Create new node
    local newNode = {
        window = window,
        left = nil,
        right = nil,
        parent = nil,
        bounds = nil
    }

    -- If tree is empty, this is the first window
    if not windowManager.tree then
        windowManager.tree = newNode
        table.insert(windowManager.windows, window)
        applyLayout()
        return
    end

    -- Find where to insert (bottom-right leaf)
    local targetNode = findBottomRightLeaf(windowManager.tree)

    if targetNode then
        -- Replace the leaf with a parent node that has two children
        local parentNode = {
            window = nil, -- Internal nodes don't have windows
            left = {
                window = targetNode.window,
                left = nil,
                right = nil,
                parent = nil,
                bounds = nil
            },
            right = newNode,
            parent = targetNode.parent,
            bounds = nil
        }

        parentNode.left.parent = parentNode
        parentNode.right.parent = parentNode

        -- Update the tree structure
        if targetNode.parent then
            if targetNode.parent.left == targetNode then
                targetNode.parent.left = parentNode
            else
                targetNode.parent.right = parentNode
            end
        else
            -- This was the root
            windowManager.tree = parentNode
        end
    end

    table.insert(windowManager.windows, window)
    applyLayout()
end

-- Remove a window from the tree
local function removeWindow(window)
    if not window then return end

    -- Remove from windows list
    for i, w in ipairs(windowManager.windows) do
        if w == window then
            table.remove(windowManager.windows, i)
            break
        end
    end

    -- Find and remove from tree
    local function findAndRemoveNode(node, targetWindow)
        if not node then return nil end

        -- If this node has the window
        if node.window == targetWindow then
            return node
        end

        -- Search children
        local leftResult = findAndRemoveNode(node.left, targetWindow)
        if leftResult then
            -- Found in left subtree
            -- Replace current node with right child
            if node.parent then
                if node.parent.left == node then
                    node.parent.left = node.right
                else
                    node.parent.right = node.right
                end
                if node.right then
                    node.right.parent = node.parent
                end
            else
                -- This was root with left child being removed
                windowManager.tree = node.right
                if node.right then
                    node.right.parent = nil
                end
            end
            return leftResult
        end

        local rightResult = findAndRemoveNode(node.right, targetWindow)
        if rightResult then
            -- Found in right subtree
            -- Replace current node with left child
            if node.parent then
                if node.parent.left == node then
                    node.parent.left = node.left
                else
                    node.parent.right = node.left
                end
                if node.left then
                    node.left.parent = node.parent
                end
            else
                -- This was root with right child being removed
                windowManager.tree = node.left
                if node.left then
                    node.left.parent = nil
                end
            end
            return rightResult
        end

        return nil
    end

    -- Special case: if it's the only window
    if windowManager.tree and windowManager.tree.window == window then
        windowManager.tree = nil
        return
    end

    findAndRemoveNode(windowManager.tree, window)
    applyLayout()
end

-- Get all managed windows
local function getAllManagedWindows()
    local allWindows = hs.window.filter.default:getWindows()
    local managed = {}

    for _, win in ipairs(allWindows) do
        if shouldManageWindow(win) then
            table.insert(managed, win)
        end
    end

    return managed
end

-- Rebuild the entire layout
local function rebuildLayout()
    -- Clear existing tree
    windowManager.tree = nil
    windowManager.windows = {}

    -- Get all windows
    local windows = getAllManagedWindows()

    -- Sort by creation time (if available) or use current order
    table.sort(windows, function(a, b)
        return a:id() < b:id()
    end)

    -- Add each window
    for _, win in ipairs(windows) do
        addWindow(win)
    end
end

-- Find node by window
local function findNodeByWindow(node, targetWindow)
    if not node then return nil end

    if node.window == targetWindow then
        return node
    end

    local leftResult = findNodeByWindow(node.left, targetWindow)
    if leftResult then return leftResult end

    return findNodeByWindow(node.right, targetWindow)
end

-- Get all leaf nodes (windows) with their bounds
local function getAllLeafNodes(node, result)
    result = result or {}

    if not node then return result end

    if not node.left and not node.right and node.window and node.bounds then
        table.insert(result, node)
    end

    getAllLeafNodes(node.left, result)
    getAllLeafNodes(node.right, result)

    return result
end

-- Find adjacent window in a direction
local function findAdjacentWindow(currentWindow, direction)
    local currentNode = findNodeByWindow(windowManager.tree, currentWindow)
    if not currentNode or not currentNode.bounds then return nil end

    local allNodes = getAllLeafNodes(windowManager.tree)
    local currentBounds = currentNode.bounds
    local currentCenterX = currentBounds.x + currentBounds.w / 2
    local currentCenterY = currentBounds.y + currentBounds.h / 2

    local bestNode = nil
    local bestDistance = math.huge

    for _, node in ipairs(allNodes) do
        if node ~= currentNode and node.window then
            local bounds = node.bounds
            local centerX = bounds.x + bounds.w / 2
            local centerY = bounds.y + bounds.h / 2

            local isCandidate = false
            local distance = 0

            if direction == "up" then
                -- Window must be above (centerY < currentCenterY)
                if centerY < currentCenterY then
                    -- Prefer windows that are horizontally aligned
                    local horizontalOverlap = math.min(currentBounds.x + currentBounds.w, bounds.x + bounds.w) -
                        math.max(currentBounds.x, bounds.x)
                    if horizontalOverlap > 0 then
                        isCandidate = true
                        distance = currentCenterY - centerY
                    end
                end
            elseif direction == "down" then
                -- Window must be below (centerY > currentCenterY)
                if centerY > currentCenterY then
                    local horizontalOverlap = math.min(currentBounds.x + currentBounds.w, bounds.x + bounds.w) -
                        math.max(currentBounds.x, bounds.x)
                    if horizontalOverlap > 0 then
                        isCandidate = true
                        distance = centerY - currentCenterY
                    end
                end
            elseif direction == "left" then
                -- Window must be to the left (centerX < currentCenterX)
                if centerX < currentCenterX then
                    local verticalOverlap = math.min(currentBounds.y + currentBounds.h, bounds.y + bounds.h) -
                        math.max(currentBounds.y, bounds.y)
                    if verticalOverlap > 0 then
                        isCandidate = true
                        distance = currentCenterX - centerX
                    end
                end
            elseif direction == "right" then
                -- Window must be to the right (centerX > currentCenterX)
                if centerX > currentCenterX then
                    local verticalOverlap = math.min(currentBounds.y + currentBounds.h, bounds.y + bounds.h) -
                        math.max(currentBounds.y, bounds.y)
                    if verticalOverlap > 0 then
                        isCandidate = true
                        distance = centerX - currentCenterX
                    end
                end
            end

            if isCandidate and distance < bestDistance then
                bestDistance = distance
                bestNode = node
            end
        end
    end

    return bestNode
end

-- Swap two windows in the tree
local function swapWindows(window1, window2)
    local node1 = findNodeByWindow(windowManager.tree, window1)
    local node2 = findNodeByWindow(windowManager.tree, window2)

    if node1 and node2 then
        -- Swap the window references
        node1.window, node2.window = node2.window, node1.window
        applyLayout()

        -- Refocus the original window at its new position
        window1:focus()
    end
end

-- Watch for window events
windowManager.watcher = hs.window.filter.new():setDefaultFilter({})
windowManager.watcher:subscribe({
    hs.window.filter.windowCreated,
    hs.window.filter.windowDestroyed,
    hs.window.filter.windowFocused
}, function(window, appName, event)
    if event == hs.window.filter.windowCreated then
        -- Only add if window should be managed
        if shouldManageWindow(window) then
            addWindow(window)
        end
    elseif event == hs.window.filter.windowDestroyed then
        removeWindow(window)
    end
end)

-- Hotkeys
hs.hotkey.bind({ "cmd", "shift" }, "M", function()
    hs.notify.new({ title = "Hammerspoon", informativeText = "Reloading configuration..." }):send()
    hs.reload()
end)

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "R", function()
    hs.notify.new({ title = "Window Manager", informativeText = "Rebuilding layout..." }):send()
    rebuildLayout()
end)

hs.hotkey.bind({ "cmd", "alt", "ctrl" }, "T", function()
    hs.notify.new({ title = "Window Manager", informativeText = "Retiling all windows..." }):send()
    applyLayout()
end)

-- Toggle blacklist for focused window
hs.hotkey.bind({ "cmd", "shift" }, "X", function()
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow then
        local app = focusedWindow:application()
        if app then
            local appName = app:name()
            local isNowBlacklisted = toggleBlacklist(appName)

            if isNowBlacklisted then
                -- App was added to blacklist
                hs.notify.new({
                    title = "Window Manager",
                    informativeText = appName .. " added to blacklist\n\nThis app's windows will no longer be tiled.",
                    contentImage = app:bundleID() and hs.image.imageFromAppBundle(app:bundleID()) or nil
                }):send()

                -- Remove all windows of this app from management
                rebuildLayout()
            else
                -- App was removed from blacklist
                hs.notify.new({
                    title = "Window Manager",
                    informativeText = appName .. " removed from blacklist\n\nThis app's windows will now be tiled.",
                    contentImage = app:bundleID() and hs.image.imageFromAppBundle(app:bundleID()) or nil
                }):send()

                -- Rebuild to include any windows from this app
                rebuildLayout()
            end

            print("Blacklist toggled for: " ..
            appName .. " (now " .. (isNowBlacklisted and "blacklisted" or "not blacklisted") .. ")")
        end
    else
        hs.notify.new({
            title = "Window Manager",
            informativeText = "No window is currently focused"
        }):send()
    end
end)

-- Window position swapping
hs.hotkey.bind({ "cmd" }, "up", function()
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow then
        local adjacentNode = findAdjacentWindow(focusedWindow, "up")
        if adjacentNode and adjacentNode.window then
            swapWindows(focusedWindow, adjacentNode.window)
        end
    end
end)

hs.hotkey.bind({ "cmd" }, "down", function()
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow then
        local adjacentNode = findAdjacentWindow(focusedWindow, "down")
        if adjacentNode and adjacentNode.window then
            swapWindows(focusedWindow, adjacentNode.window)
        end
    end
end)

hs.hotkey.bind({ "cmd" }, "left", function()
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow then
        local adjacentNode = findAdjacentWindow(focusedWindow, "left")
        if adjacentNode and adjacentNode.window then
            swapWindows(focusedWindow, adjacentNode.window)
        end
    end
end)

hs.hotkey.bind({ "cmd" }, "right", function()
    local focusedWindow = hs.window.focusedWindow()
    if focusedWindow then
        local adjacentNode = findAdjacentWindow(focusedWindow, "right")
        if adjacentNode and adjacentNode.window then
            swapWindows(focusedWindow, adjacentNode.window)
        end
    end
end)

-- Initialize
-- Load saved blacklist or save default
if not loadBlacklist() then
    saveBlacklist() -- Save default blacklist if no file exists
end

hs.notify.new({ title = "Hammerspoon", informativeText = "Recursive Window Tiler loaded!" }):send()
print("Recursive Window Tiler loaded!")
print("Cmd+Shift+M: Reload configuration")
print("Cmd+Alt+Ctrl+R: Rebuild layout")
print("Cmd+Alt+Ctrl+T: Retile windows")
print("Cmd+Arrow Keys: Swap window positions")
print("Cmd+Shift+X: Toggle blacklist for focused app")
print("")
print("Blacklisted apps: " .. table.concat(windowManager.blacklist, ", "))

-- Initial layout
rebuildLayout()
