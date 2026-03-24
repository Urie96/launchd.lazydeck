local M = {}

-- 辅助函数：获取当前选中的服务信息
local function get_selected_service()
  local entry = lc.api.page_get_hovered()
  if not entry or not entry.label then return nil end
  return entry
end

-- 辅助函数：获取服务的启用状态
local function get_service_status(service_info, callback)
  local domain = service_info.domain
  local label = service_info.label

  -- 构建命令参数
  local cmd = { 'launchctl', 'print-disabled', domain }

  -- 检查 print-disabled 输出
  lc.system(cmd, function(out)
    if out.code ~= 0 then
      callback {
        is_enabled = true, -- 默认假设启用
      }
      return
    end

    -- 解析输出，查找该服务的状态
    local enabled = true
    -- 转义标签中的特殊字符用于模式匹配
    local label_pattern = '"' .. label:gsub('([^%w])', '%%%1') .. '"'
    if out.stdout:match(label_pattern .. '%s*=>%s*disabled') then enabled = false end

    callback {
      is_enabled = enabled,
    }
  end)
end

-- 辅助函数：执行服务操作
local function do_service_action(action_name)
  local service_info = get_selected_service()
  if not service_info then
    lc.notify 'Please select a service first'
    return
  end

  local cmd = { 'launchctl' }
  local label = service_info.label ---@type string
  local target = service_info.domain .. '/' .. label

  -- 根据操作类型构建命令
  if action_name == 'start' then
    table.insert(cmd, 'start')
    table.insert(cmd, label)
  elseif action_name == 'stop' then
    table.insert(cmd, 'stop')
    table.insert(cmd, label)
  elseif action_name == 'bootout' then
    table.insert(cmd, 'bootout')
    table.insert(cmd, target)
  elseif action_name == 'enable' then
    table.insert(cmd, 'enable')
    table.insert(cmd, target)
  elseif action_name == 'disable' then
    table.insert(cmd, 'disable')
    table.insert(cmd, target)
  elseif action_name == 'kill' then
    table.insert(cmd, 'kill')
    table.insert(cmd, target)
    table.insert(cmd, 'SIGTERM') -- 发送 SIGTERM 信号
  elseif action_name == 'kill9' then
    table.insert(cmd, 'kill')
    table.insert(cmd, target)
    table.insert(cmd, 'SIGKILL') -- 发送 SIGKILL 信号
  elseif action_name == 'print' then
    table.insert(cmd, 'print')
    table.insert(cmd, target)
  else
    lc.notify('Unknown action: ' .. action_name)
    return
  end

  -- 执行命令
  lc.interactive(cmd, { wait_confirm = function(exit_code) return exit_code ~= 0 end }, function(exit_code)
    if exit_code == 0 then
      lc.notify(action_name .. ' for ' .. label .. ' successful')
      lc.cmd 'reload'
    else
      lc.notify(action_name .. ' for ' .. label .. ' failed')
    end
  end)
end

function M.start() do_service_action 'start' end
function M.stop() do_service_action 'stop' end
function M.bootout() do_service_action 'bootout' end
function M.enable() do_service_action 'enable' end
function M.disable() do_service_action 'disable' end
function M.kill() do_service_action 'kill' end
function M.kill9() do_service_action 'kill9' end

-- 显示可用操作的选择对话框
function M.select_action()
  local service_info = get_selected_service()
  if not service_info then
    lc.notify 'Please select a service first'
    return
  end

  get_service_status(service_info, function(status)
    local options = {}

    -- 根据状态显示不同操作
    -- 如果 PID 不是 '-'，说明服务正在运行（可能有错误或正常）
    if service_info.pid ~= '-' then
      table.insert(options, {
        value = 'stop',
        display = lc.style.line { ('⏹️ Stop'):fg 'red' },
      })
      table.insert(options, {
        value = 'kill',
        display = lc.style.line { ('💀 Kill (SIGTERM)'):fg 'red' },
      })
      table.insert(options, {
        value = 'kill9',
        display = lc.style.line { ('☠️ Kill (SIGKILL)'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'start',
        display = lc.style.line { ('▶️ Start'):fg 'green' },
      })
    end

    -- 启用/禁用操作
    if status.is_enabled then
      table.insert(options, {
        value = 'disable',
        display = lc.style.line { ('🔓 Disable'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'enable',
        display = lc.style.line { ('🔒 Enable'):fg 'green' },
      })
    end

    table.insert(options, {
      value = 'bootout',
      display = lc.style.line { ('🗑️ '):fg 'red' },
    })

    lc.select({
      prompt = 'Select an action for ' .. service_info.label,
      options = options,
    }, function(choice)
      if choice then M[choice]() end
    end)
  end)
end

return M
