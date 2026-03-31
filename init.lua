-- ============================================
-- Right Command -> switch IME -> double tap Left Option
-- 放到 ~/.hammerspoon/init.lua
-- 版本：保持当前可用行为，只修监听容易失效的问题
-- ============================================

local log = hs.logger.new("RightCmdIME", "debug")
local alert = hs.alert

-- 目标输入法
local TARGET_INPUT_SOURCE = "com.bytedance.inputmethod.doubaoime.pinyin"

-- 右侧 Command 按下后，多久再执行双击左 Option（秒）
local OPTION_PRESS_DELAY = 0.30

-- 两次 Option 点击之间的间隔（秒）
local OPTION_DOUBLE_TAP_INTERVAL = 0.08

-- 松开右 Command 后，延迟多久恢复原输入法（秒）
local RESTORE_IME_DELAY = 2.0

-- 物理按键 keycode
local KEYCODE_RIGHT_CMD = 54

-- 状态变量
local previousInputSource = nil
local rightCmdIsDown = false
local optionPressTimer = nil
local restoreImeTimer = nil

local function nowSource()
    return hs.keycodes.currentSourceID()
end

local function tapLeftOptionOnce()
    hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, true):post()
    hs.eventtap.event.newKeyEvent(hs.keycodes.map.alt, false):post()
    log.df("已模拟单击左 Option")
end

local function doubleTapLeftOption()
    log.df("开始模拟双击左 Option")
    tapLeftOptionOnce()

    hs.timer.doAfter(OPTION_DOUBLE_TAP_INTERVAL, function()
        tapLeftOptionOnce()
        log.df("已完成双击左 Option")
    end)
end

local function cancelOptionTimer()
    if optionPressTimer then
        optionPressTimer:stop()
        optionPressTimer = nil
        log.df("已取消待执行的 Option 定时器")
    end
end

local function cancelRestoreImeTimer()
    if restoreImeTimer then
        restoreImeTimer:stop()
        restoreImeTimer = nil
        log.df("已取消待执行的输入法恢复定时器")
    end
end

local function switchToTargetIME()
    local current = nowSource()
    previousInputSource = current
    log.df("记录当前输入法: %s", tostring(current))

    if current == TARGET_INPUT_SOURCE then
        log.df("当前已经是目标输入法，无需切换: %s", TARGET_INPUT_SOURCE)
        return
    end

    local ok = hs.keycodes.currentSourceID(TARGET_INPUT_SOURCE)
    log.df("切换到目标输入法: %s, 结果: %s", TARGET_INPUT_SOURCE, tostring(ok))
end

local function restorePreviousIME()
    if not previousInputSource then
        log.df("没有记录到之前的输入法，跳过恢复")
        return
    end

    if previousInputSource == TARGET_INPUT_SOURCE then
        log.df("之前输入法本来就是目标输入法，无需恢复")
        previousInputSource = nil
        return
    end

    local old = previousInputSource
    local ok = hs.keycodes.currentSourceID(old)
    log.df("恢复之前输入法: %s, 结果: %s", tostring(old), tostring(ok))
    previousInputSource = nil
end

local function scheduleRestorePreviousIME()
    cancelRestoreImeTimer()

    restoreImeTimer = hs.timer.doAfter(RESTORE_IME_DELAY, function()
        restoreImeTimer = nil
        log.df("延迟 %.2f 秒后，开始恢复之前输入法", RESTORE_IME_DELAY)
        restorePreviousIME()
    end)

    log.df("已安排 %.2f 秒后恢复之前输入法", RESTORE_IME_DELAY)
end

local function onRightCmdDown()
    if rightCmdIsDown then
        log.df("右 Command 已处于按下状态，忽略重复事件")
        return
    end

    rightCmdIsDown = true
    log.df("检测到右 Command 按下")

    -- 新一轮开始时，取消上一次尚未执行的恢复动作
    cancelRestoreImeTimer()

    switchToTargetIME()

    cancelOptionTimer()
    optionPressTimer = hs.timer.doAfter(OPTION_PRESS_DELAY, function()
        optionPressTimer = nil

        if rightCmdIsDown then
            log.df("延迟结束，右 Command 仍按着，准备双击左 Option")
            doubleTapLeftOption()
        else
            log.df("延迟结束时右 Command 已松开，不再双击左 Option")
        end
    end)
end

local function onRightCmdUp()
    if not rightCmdIsDown then
        log.df("右 Command 当前并非按下状态，忽略松开事件")
        return
    end

    rightCmdIsDown = false
    log.df("检测到右 Command 松开")

    cancelOptionTimer()
    doubleTapLeftOption()

    -- 延迟恢复原输入法
    scheduleRestorePreviousIME()
end

-- 核心修复 1：只要检测到 rightcmd 的 flagsChanged，
-- 就根据内部状态翻转，而不是依赖 flags.cmd
local function handleRightCmdFlagsChanged(event)
    local keycode = event:getKeyCode()
    local flags = event:getFlags()

    if keycode ~= KEYCODE_RIGHT_CMD then
        return false
    end

    log.df(
        "flagsChanged: keycode=%s, cmd=%s, alt=%s, shift=%s, ctrl=%s, rightCmdIsDown=%s",
        tostring(keycode),
        tostring(flags.cmd),
        tostring(flags.alt),
        tostring(flags.shift),
        tostring(flags.ctrl),
        tostring(rightCmdIsDown)
    )

    if rightCmdIsDown then
        onRightCmdUp()
    else
        onRightCmdDown()
    end

    return false
end

-- 核心修复 2：避免回调异常导致 watcher 看起来“死掉”
local function safeEventHandler(event)
    local ok, result = xpcall(function()
        return handleRightCmdFlagsChanged(event)
    end, debug.traceback)

    if not ok then
        log.ef("eventtap 回调报错:\n%s", tostring(result))
        return false
    end

    return result
end

-- 放到全局，尽量避免 reload / GC 等边缘情况
_G.rightCmdWatcher = hs.eventtap.new(
    { hs.eventtap.event.types.flagsChanged },
    safeEventHandler
)

_G.rightCmdWatcher:start()

alert.show("RightCmdIME 脚本已启动")
log.i(string.format("目标输入法: %s", TARGET_INPUT_SOURCE))
log.i(string.format("右 Command keycode=%d", KEYCODE_RIGHT_CMD))
log.i(string.format("恢复输入法延迟=%.2f 秒", RESTORE_IME_DELAY))