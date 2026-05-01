-- ============================================
-- Fn tap -> Doubao voice input -> restore IME
-- Put this file at ~/.hammerspoon/init.lua
-- ============================================

pcall(function()
    hs.ipc.cliInstall()
end)

local log = hs.logger.new("DoubaoVoice", "debug")
local alert = hs.alert

-- Doubao IME as installed on macOS:
--   /Library/Input Methods/DoubaoIme.app
local TARGET_INPUT_SOURCE_ID = "com.bytedance.inputmethod.doubaoime.pinyin"
local TARGET_INPUT_METHOD = "豆包输入法"

-- Daily input sources. Ctrl+Space toggles only between these two.
local NORMAL_CHINESE_INPUT_METHOD = "Squirrel - Simplified"
local NORMAL_ENGLISH_KEYBOARD_LAYOUT = "U.S."

-- Timing knobs for the tap-to-toggle model.
local ACTION_AFTER_FN_UP_DELAY = 0.02
local VOICE_TRIGGER_AFTER_SWITCH_DELAY = 0.08
local INPUT_SOURCE_SWITCH_TIMEOUT = 2.0
local INPUT_SOURCE_POLL_INTERVAL = 0.01
local INPUT_METHOD_BRIDGE_DELAY = 0.15
local OPTION_TAP_HOLD_DURATION = 0.025
local OPTION_DOUBLE_TAP_INTERVAL = 0.07
local RESTORE_AFTER_VOICE_STOP_DELAY = 1.0

local KEYCODE_OPTION = 58
local KEYCODE_FN = 63
local KEYCODE_SPACE = 49

local previousInputSource = nil
local sourceBeforeFnTap = nil
local lastNonDoubaoInputSource = nil
local doubaoVoiceActive = false
local fnIsDown = false
local fnWasUsedWithOtherKey = false
local pendingActionTimer = nil
local restoreImeTimer = nil

local function nowSource()
    local sourceID = hs.keycodes.currentSourceID()
    local method = hs.keycodes.currentMethod()
    if method ~= nil then
        return {
            kind = "method",
            value = method,
            sourceID = sourceID
        }
    end

    local layout = hs.keycodes.currentLayout()
    if layout ~= nil then
        return {
            kind = "layout",
            value = layout,
            sourceID = sourceID
        }
    end

    return nil
end

local function cancelPendingActionTimer()
    if pendingActionTimer then
        pendingActionTimer:stop()
        pendingActionTimer = nil
    end
end

local function cancelRestoreImeTimer()
    if restoreImeTimer then
        restoreImeTimer:stop()
        restoreImeTimer = nil
    end
end

local function setDoubaoIME()
    local ok = hs.keycodes.currentSourceID(TARGET_INPUT_SOURCE_ID)
    log.df("按 source id 切换到豆包输入法: %s, 结果: %s", TARGET_INPUT_SOURCE_ID, tostring(ok))

    if not ok then
        ok = hs.keycodes.setMethod(TARGET_INPUT_METHOD)
        log.df("按 method 名称切换到豆包输入法: %s, 结果: %s", TARGET_INPUT_METHOD, tostring(ok))
    end

    return ok
end

local function isDoubaoIMEActive()
    return hs.keycodes.currentSourceID() == TARGET_INPUT_SOURCE_ID
        or hs.keycodes.currentMethod() == TARGET_INPUT_METHOD
end

local function isNormalChineseInputMethodActive()
    return hs.keycodes.currentMethod() == NORMAL_CHINESE_INPUT_METHOD
end

local function defaultNormalChineseInputSource()
    return {
        kind = "method",
        value = NORMAL_CHINESE_INPUT_METHOD
    }
end

local function isDoubaoInputSource(source)
    return source
        and (source.sourceID == TARGET_INPUT_SOURCE_ID
            or (source.kind == "method" and source.value == TARGET_INPUT_METHOD))
end

local function rememberLastNonDoubaoInputSource()
    local source = nowSource()
    if source and not isDoubaoInputSource(source) then
        lastNonDoubaoInputSource = source
        log.df("记录最近非豆包输入源 %s: %s", tostring(source.kind), tostring(source.value))
    end
end

local function restoreTargetFrom(candidate)
    if candidate and not isDoubaoInputSource(candidate) then
        return candidate
    end

    return lastNonDoubaoInputSource or defaultNormalChineseInputSource()
end

local function waitForInputSource(description, isReady, onReady, deadline)
    if isReady() then
        onReady()
        return
    end

    deadline = deadline or (hs.timer.secondsSinceEpoch() + INPUT_SOURCE_SWITCH_TIMEOUT)

    if hs.timer.secondsSinceEpoch() >= deadline then
        log.ef("等待%s生效超时: currentSourceID=%s, currentMethod=%s, currentLayout=%s",
            description,
            tostring(hs.keycodes.currentSourceID()),
            tostring(hs.keycodes.currentMethod()),
            tostring(hs.keycodes.currentLayout()))
        alert.show(description .. "切换超时")
        return
    end

    hs.timer.doAfter(INPUT_SOURCE_POLL_INTERVAL, function()
        waitForInputSource(description, isReady, onReady, deadline)
    end)
end

local function waitForDoubaoIME(onReady)
    waitForInputSource("豆包输入法", isDoubaoIMEActive, function()
        hs.timer.doAfter(VOICE_TRIGGER_AFTER_SWITCH_DELAY, onReady)
    end)
end

local function waitForNormalChineseInputMethod(onReady)
    waitForInputSource("日常中文输入法", isNormalChineseInputMethodActive, function()
        hs.timer.doAfter(INPUT_METHOD_BRIDGE_DELAY, onReady)
    end)
end

local function restorePreviousIME()
    if not previousInputSource then
        log.df("没有记录到之前的输入来源，恢复到默认中文输入法")
    end

    local old = restoreTargetFrom(previousInputSource)
    local ok = false

    if old.kind == "method" then
        ok = hs.keycodes.setMethod(old.value)
        log.df("恢复之前输入法 method: %s, 结果: %s", tostring(old.value), tostring(ok))
    elseif old.kind == "layout" then
        ok = hs.keycodes.setLayout(old.value)
        log.df("恢复之前键盘布局 layout: %s, 结果: %s", tostring(old.value), tostring(ok))
    end

    previousInputSource = nil
end

local function modifiersAreClear()
    local mods = hs.eventtap.checkKeyboardModifiers()
    return not mods.cmd and not mods.alt and not mods.shift and not mods.ctrl and not mods.fn
end

local function runWhenModifiersClear(fn, attemptsLeft)
    attemptsLeft = attemptsLeft or 30

    if modifiersAreClear() or attemptsLeft <= 0 then
        fn()
        return
    end

    hs.timer.doAfter(0.01, function()
        runWhenModifiersClear(fn, attemptsLeft - 1)
    end)
end

local function postLeftOptionFlagsChanged(isDown)
    local rawMasks = hs.eventtap.event.rawFlagMasks
    local rawFlags = rawMasks.nonCoalesced

    if isDown then
        rawFlags = rawFlags + rawMasks.alternate + rawMasks.deviceLeftAlternate
    end

    hs.eventtap.event.newEvent()
        :setType(hs.eventtap.event.types.flagsChanged)
        :setProperty(hs.eventtap.event.properties.keyboardEventKeycode, KEYCODE_OPTION)
        :setFlags(isDown and {alt = true} or {})
        :rawFlags(rawFlags)
        :post()
end

local function tapLeftOptionOnce(done)
    postLeftOptionFlagsChanged(true)

    hs.timer.doAfter(OPTION_TAP_HOLD_DURATION, function()
        postLeftOptionFlagsChanged(false)

        if done then
            done()
        end
    end)
end

local function doubleTapLeftOption(done)
    runWhenModifiersClear(function()
        log.df("发送豆包语音快捷键：左 Option 双击")

        tapLeftOptionOnce(function()
            hs.timer.doAfter(OPTION_DOUBLE_TAP_INTERVAL, function()
                tapLeftOptionOnce(done)
            end)
        end)
    end)
end

local function startDoubaoVoice()
    cancelRestoreImeTimer()
    previousInputSource = restoreTargetFrom(sourceBeforeFnTap or nowSource())
    sourceBeforeFnTap = nil

    local function switchToDoubaoAndTrigger()
        if not isDoubaoIMEActive() and not setDoubaoIME() then
            alert.show("未能切换到豆包输入法")
            return
        end

        waitForDoubaoIME(function()
            doubleTapLeftOption(function()
                doubaoVoiceActive = true
                log.df("豆包语音输入已启动，等待再次按 Fn 停止")
            end)
        end)
    end

    if isDoubaoIMEActive() then
        switchToDoubaoAndTrigger()
        return
    end

    if previousInputSource and previousInputSource.kind == "layout" then
        local ok = hs.keycodes.setMethod(NORMAL_CHINESE_INPUT_METHOD)
        log.df("当前是键盘布局 %s，先桥接到日常中文输入法 %s，结果: %s",
            tostring(previousInputSource.value),
            NORMAL_CHINESE_INPUT_METHOD,
            tostring(ok))

        if ok then
            waitForNormalChineseInputMethod(switchToDoubaoAndTrigger)
            return
        end
    end

    switchToDoubaoAndTrigger()
end

local function stopDoubaoVoice()
    doubleTapLeftOption(function()
        doubaoVoiceActive = false

        cancelRestoreImeTimer()
        restoreImeTimer = hs.timer.doAfter(RESTORE_AFTER_VOICE_STOP_DELAY, restorePreviousIME)
        log.df("豆包语音输入已停止，已安排恢复之前输入法")
    end)
end

local function toggleDoubaoVoice()
    if doubaoVoiceActive then
        stopDoubaoVoice()
    else
        startDoubaoVoice()
    end
end

local function scheduleDoubaoToggle()
    cancelPendingActionTimer()

    pendingActionTimer = hs.timer.doAfter(ACTION_AFTER_FN_UP_DELAY, function()
        pendingActionTimer = nil
        toggleDoubaoVoice()
    end)
end

local function handleFnFlagsChanged(event)
    local flags = event:getFlags()

    if flags.fn and not fnIsDown then
        fnIsDown = true
        fnWasUsedWithOtherKey = false
        sourceBeforeFnTap = nowSource()
        return true
    end

    if not flags.fn and fnIsDown then
        fnIsDown = false

        if not fnWasUsedWithOtherKey then
            scheduleDoubaoToggle()
        else
            sourceBeforeFnTap = nil
        end

        fnWasUsedWithOtherKey = false
        return true
    end

    return false
end

local function safeFnHandler(event)
    local ok, shouldDelete = xpcall(function()
        return handleFnFlagsChanged(event)
    end, debug.traceback)

    if not ok then
        log.ef("Fn 回调报错:\n%s", tostring(shouldDelete))
        return false
    end

    return shouldDelete
end

local function toggleNormalInputSource()
    local currentSourceID = hs.keycodes.currentSourceID()
    local currentMethod = hs.keycodes.currentMethod()
    local currentLayout = hs.keycodes.currentLayout()

    log.df("Ctrl+Space: currentSourceID=%s, currentMethod=%s, currentLayout=%s",
        tostring(currentSourceID), tostring(currentMethod), tostring(currentLayout))

    if currentSourceID == TARGET_INPUT_SOURCE_ID or currentMethod == NORMAL_CHINESE_INPUT_METHOD then
        local ok = hs.keycodes.setLayout(NORMAL_ENGLISH_KEYBOARD_LAYOUT)
        log.df("Ctrl+Space: 切换到英文键盘布局 %s, 结果: %s",
            NORMAL_ENGLISH_KEYBOARD_LAYOUT, tostring(ok))
        return
    end

    local ok = hs.keycodes.setMethod(NORMAL_CHINESE_INPUT_METHOD)
    log.df("Ctrl+Space: 切换到中文输入法 %s, 结果: %s",
        NORMAL_CHINESE_INPUT_METHOD, tostring(ok))
end

local function handleKeyDown(event)
    if fnIsDown and event:getKeyCode() ~= KEYCODE_FN then
        fnWasUsedWithOtherKey = true
    end

    if event:getKeyCode() ~= KEYCODE_SPACE then
        return false
    end

    local flags = event:getFlags()
    if not flags.ctrl or flags.cmd or flags.alt or flags.shift or flags.fn then
        return false
    end

    local isRepeat = event:getProperty(hs.eventtap.event.properties.keyboardEventAutorepeat) == 1
    if not isRepeat then
        toggleNormalInputSource()
    end

    return true
end

local function safeKeyDownHandler(event)
    local ok, result = xpcall(function()
        return handleKeyDown(event)
    end, debug.traceback)

    if not ok then
        log.ef("keyDown 回调报错:\n%s", tostring(result))
        return false
    end

    return result
end

-- Keep watchers in globals so Lua GC will not collect them.
_G.fnVoiceWatcher = hs.eventtap.new({hs.eventtap.event.types.flagsChanged}, safeFnHandler)
_G.fnVoiceWatcher:start()

_G.fnCombinationWatcher = hs.eventtap.new({hs.eventtap.event.types.keyDown}, safeKeyDownHandler)
_G.fnCombinationWatcher:start()

rememberLastNonDoubaoInputSource()
hs.keycodes.inputSourceChanged(rememberLastNonDoubaoInputSource)

alert.show("Doubao voice shortcut loaded")
log.i(string.format("目标输入法 source id: %s", TARGET_INPUT_SOURCE_ID))
log.i("Fn 轻按：启动/停止豆包语音输入")
log.i(string.format("Ctrl+Space 仅在 %s / %s 之间切换",
    NORMAL_CHINESE_INPUT_METHOD, NORMAL_ENGLISH_KEYBOARD_LAYOUT))
