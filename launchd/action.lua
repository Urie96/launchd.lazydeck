local config = require 'launchd.config'
local plist = require 'launchd.plist'

local M = {}

local function line(parts) return lc.style.line(parts) end
local function text(lines) return lc.style.text(lines) end
local function span(value, color)
  local s = lc.style.span(tostring(value or ''))
  if color and color ~= '' then s = s:fg(color) end
  return s
end

local function candidate_domains(service_info)
  local domains = {}
  local seen = {}

  local function add(value)
    if not value or value == '' or seen[value] then return end
    seen[value] = true
    table.insert(domains, value)
  end

  add(service_info.domain)
  add(config.get().domain)
  add 'system'

  local uid = tostring(config.get().domain or ''):match '^gui/(%d+)$' or tostring(config.get().domain or ''):match '^user/(%d+)$'
  if uid then
    add('gui/' .. uid)
    add('user/' .. uid)
  end

  return domains
end

local function resolve_target(service_info, callback)
  local domains = candidate_domains(service_info)
  local index = 1

  local function try_next()
    local domain = domains[index]
    index = index + 1

    if not domain then
      callback(service_info.domain .. '/' .. service_info.label, service_info.domain, false)
      return
    end

    local target = domain .. '/' .. service_info.label
    lc.system({ config.get().command, 'print', target }, function(out)
      if out.code == 0 then
        callback(target, domain, true, out.stdout)
        return
      end
      try_next()
    end)
  end

  try_next()
end

-- 辅助函数：获取当前选中的服务信息
local function get_selected_service()
  local entry = lc.api.page_get_hovered()
  if not entry or entry.kind ~= 'service' or not entry.label then return nil end
  return entry
end

-- 辅助函数：获取服务的启用状态
local function get_service_status(service_info, callback)
  resolve_target(service_info, function(_, domain)
    lc.system({ config.get().command, 'print-disabled', domain }, function(out)
      if out.code ~= 0 then
        callback {
          is_enabled = true,
          domain = domain,
        }
        return
      end

      local enabled = true
      local label_pattern = '"' .. service_info.label:gsub('([^%w])', '%%%1') .. '"'
      if out.stdout:match(label_pattern .. '%s*=>%s*disabled') then enabled = false end

      callback {
        is_enabled = enabled,
        domain = domain,
      }
    end)
  end)
end

-- 辅助函数：执行服务操作
local function do_service_action(action_name)
  local service_info = get_selected_service()
  if not service_info then
    lc.notify 'Please select a service first'
    return
  end

  local cmd = { config.get().command }
  local label = service_info.label ---@type string
  resolve_target(service_info, function(target, domain)
    service_info.domain = domain

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
      table.insert(cmd, 'SIGTERM')
    elseif action_name == 'kill9' then
      table.insert(cmd, 'kill')
      table.insert(cmd, target)
      table.insert(cmd, 'SIGKILL')
    elseif action_name == 'print' then
      table.insert(cmd, 'print')
      table.insert(cmd, target)
    else
      lc.notify('Unknown action: ' .. action_name)
      return
    end

    lc.interactive(cmd, { wait_confirm = function(exit_code) return exit_code ~= 0 end }, function(exit_code)
      if exit_code == 0 then
        lc.notify(action_name .. ' for ' .. label .. ' successful')
        lc.cmd 'reload'
      else
        lc.notify(action_name .. ' for ' .. label .. ' failed')
      end
    end)
  end)
end

function M.start() do_service_action 'start' end
function M.stop() do_service_action 'stop' end
function M.bootout() do_service_action 'bootout' end
function M.enable() do_service_action 'enable' end
function M.disable() do_service_action 'disable' end
function M.kill() do_service_action 'kill' end
function M.kill9() do_service_action 'kill9' end

function M.preview_service(entry, cb)
  if not entry or not entry.label then
    cb(text {
      line { span('Select a service to view details', 'darkgray') },
    })
    return
  end

  resolve_target(entry, function(_, domain, found, stdout)
    if not found then
      local pid = entry.pid == '-' and 'not running' or entry.pid
      cb(text {
        line { span('Label', 'cyan'), span(': ' .. entry.label, 'white') },
        line { span('PID', 'cyan'), span(': ' .. pid, 'white') },
        line { span('Status', 'cyan'), span(': ' .. tostring(entry.status or ''), 'white') },
        line { span('Domain', 'cyan'), span(': ' .. entry.domain, 'white') },
        line { '' },
        line { span('Unable to get detailed info', 'red') },
      })
      return
    end

    entry.domain = domain
    local parsed = plist.decode(stdout)
    local data = parsed
    for _, value in pairs(parsed) do
      if type(value) == 'table' then
        data = value
        break
      end
    end

    local lines = {
      line { span('Label', 'cyan'), span(': ' .. entry.label, 'white') },
    }

    if data.domain then
      local domain_str = type(data.domain) == 'table' and table.concat(data.domain, ' ') or tostring(data.domain)
      table.insert(lines, line { span('Domain', 'cyan'), span(': ' .. domain_str, 'white') })
    end
    if data.state then
      local state_str = tostring(data.state)
      local state_color = state_str == 'running' and 'green' or (state_str == 'stopped' and 'red' or 'yellow')
      table.insert(lines, line { span('State', 'cyan'), span(': ' .. state_str, state_color) })
    end

    local pid = data.pid and tostring(data.pid) or entry.pid
    table.insert(lines, line { span('PID', 'cyan'), span(': ' .. (pid == '-' and 'not running' or tostring(pid)), 'white') })

    if data.type then table.insert(lines, line { span('Type', 'cyan'), span(': ' .. tostring(data.type), 'white') }) end
    if data.path then table.insert(lines, line { span('Path', 'cyan'), span(': ' .. tostring(data.path), 'blue') }) end
    if data.program then table.insert(lines, line { span('Program', 'cyan'), span(': ' .. tostring(data.program), 'green') }) end
    if data.arguments then
      local args = type(data.arguments) == 'table' and table.concat(data.arguments, ' ') or tostring(data.arguments)
      table.insert(lines, line { span('Arguments', 'cyan'), span(': ' .. args, 'green') })
    end
    if data.runs then table.insert(lines, line { span('Runs', 'cyan'), span(': ' .. tostring(data.runs), 'white') }) end
    if data['last exit code'] then
      local exit_code = tostring(data['last exit code'])
      local exit_color = (exit_code == '0' or exit_code == '(never exited)') and 'green' or 'red'
      table.insert(lines, line { span('Last Exit Code', 'cyan'), span(': ' .. exit_code, exit_color) })
    end
    if data['spawn type'] then
      table.insert(lines, line { span('Spawn Type', 'cyan'), span(': ' .. tostring(data['spawn type']), 'yellow') })
    end
    if data.properties then
      if type(data.properties) == 'table' then
        local props = {}
        for key, _ in pairs(data.properties) do
          table.insert(props, tostring(key))
        end
        table.sort(props)
        if #props > 0 then
          table.insert(lines, line { span('Properties', 'cyan'), span(': ' .. table.concat(props, ' | '), 'magenta') })
        end
      else
        table.insert(lines, line { span('Properties', 'cyan'), span(': ' .. tostring(data.properties), 'magenta') })
      end
    end

    cb(text(lines))
  end)
end

function M.preview_info(entry)
  return text {
    line { span(entry.title or 'launchd', 'cyan') },
    line { span(entry.message or '', entry.color or 'darkgray') },
    line { span(entry.detail or '', 'darkgray') },
  }
end

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
        display = lc.style.line { ('󰓛 Stop'):fg 'red' },
      })
      table.insert(options, {
        value = 'kill',
        display = lc.style.line { ('󰚌 Kill (SIGTERM)'):fg 'red' },
      })
      table.insert(options, {
        value = 'kill9',
        display = lc.style.line { ('󰚌 Kill (SIGKILL)'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'start',
        display = lc.style.line { ('󰐊 Start'):fg 'green' },
      })
    end

    -- 启用/禁用操作
    if status.is_enabled then
      table.insert(options, {
        value = 'disable',
        display = lc.style.line { ('󰌾 Disable'):fg 'red' },
      })
    else
      table.insert(options, {
        value = 'enable',
        display = lc.style.line { ('󰌿 Enable'):fg 'green' },
      })
    end

    table.insert(options, {
      value = 'bootout',
      display = lc.style.line { ('󰩺 Bootout'):fg 'red' },
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
