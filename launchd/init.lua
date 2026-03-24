-- launchd.lazycmd - macOS launchd service manager

local M = {}

local uid = (function()
  local handle = io.popen 'id -u'
  if handle then
    local uid = handle:read '*a'
    handle:close()
    return uid:gsub('%s+', '')
  end
  return '501' -- 默认值
end)()

local domain = (function()
  if uid == 0 then
    return 'system'
  else
    return 'gui/' .. tostring(uid)
  end
end)()

-- 构建目标域
local function get_domain() end

function M.setup()
  lc.keymap.set('main', '<enter>', function() require('launchd.action').select_action() end)
end

function M.list(_, cb)
  -- 使用 list 命令获取服务列表
  lc.system({ 'launchctl', 'list' }, function(out)
    if out.code ~= 0 then
      lc.log('error', 'Failed to list services: {}', out.stderr or 'Unknown error')
      cb {}
      return
    end

    -- 解析输出
    local entries = {}
    local lines = out.stdout:split '\n'

    for i, line in ipairs(lines) do
      -- 跳过空行和表头
      if i == 1 or line:trim() == '' or line:match '^PID' then goto continue end

      -- 将连续空格替换为单个空格
      local parts = line:gsub('%s+', ' '):trim():split ' '

      if #parts >= 3 then
        local pid = parts[1]
        local status = parts[2]
        local label = parts[3]

        -- 根据 PID 确定状态（status 是上次退出码，不表示当前错误）
        local category = 'stopped'
        local display = label

        if pid ~= '-' then
          -- 正在运行（不管上次退出码是什么）
          category = 'running'
          display = display:fg 'green'
        else
          -- 已停止
          category = 'stopped'
          if status == '0' then
            -- 上次正常退出
            display = display:fg 'gray'
          else
            -- 上次异常退出
            category = 'failed'
            display = display:fg 'yellow'
          end
        end

        table.insert(entries, {
          key = label,
          label = label,
          pid = pid,
          status = status,
          display = display,
          domain = domain,
          category = category,
        })
      end

      ::continue::
    end

    cb(entries)
  end)
end

function M.preview(entry, cb)
  if not entry or not entry.label then
    cb 'Select a service to view details'
    return
  end

  local target = domain .. '/' .. entry.label

  lc.system({ 'launchctl', 'print', target }, function(out)
    if out.code ~= 0 then
      -- 如果 print 失败，显示基本信息（带样式）
      local pid = entry.pid == '-' and 'not running' or entry.pid
      local lines = {
        lc.style.line({ '🏷️  Label: ', entry.label }):fg 'magenta',
        lc.style.line({ '🆔 PID: ', pid }):fg 'cyan',
        lc.style.line({ '📊 Status: ', entry.status }):fg 'yellow',
        lc.style.line({ '📍 Domain: ', domain }):fg 'blue',
        '',
        lc.style.line({ '❌ Unable to get detailed info' }):fg 'red',
      }
      lc.style.align_columns(lines)
      cb(lc.style.text(lines))
      return
    end

    -- 使用 plist.lua 解析输出
    local plist = require 'launchd.plist'
    local parsed = plist.decode(out.stdout)

    -- 解析后的数据结构是：{ ['gui/501/label'] = { key = value, ... } }
    -- 需要获取实际的键值对
    local data = parsed
    for k, v in pairs(parsed) do
      if type(v) == 'table' then
        data = v
        break
      end
    end

    -- 提取关键信息并使用样式化显示
    local lines = {
      lc.style.line({ '🏷️  Label: ', entry.label }):fg 'magenta',
    }

    -- 提取目标路径（如 gui/501/xxx）
    if data.domain then
      local domain_str = type(data.domain) == 'table' and table.concat(data.domain, ' ') or tostring(data.domain)
      table.insert(lines, lc.style.line({ '📍 Domain: ', domain_str }):fg 'blue')
    end

    -- 提取状态
    if data.state then
      local state_str = tostring(data.state)
      local state_color = state_str == 'running' and 'green' or (state_str == 'stopped' and 'red' or 'yellow')
      table.insert(lines, lc.style.line({ '📊 State: ', state_str }):fg(state_color))
    end

    -- 提取 PID
    local pid = entry.pid == '-' and '-' or entry.pid
    if data.pid then pid = tostring(data.pid) end
    local pid_str = pid == '-' and 'not running' or pid
    local pid_color = pid == '-' and 'gray' or 'cyan'
    table.insert(lines, lc.style.line({ '🆔 PID: ', pid_str }):fg(pid_color))

    -- 提取服务类型
    if data.type then table.insert(lines, lc.style.line({ '📦 Type: ', tostring(data.type) }):fg 'yellow') end

    -- 提取路径
    if data.path then table.insert(lines, lc.style.line({ '📄 Path: ', tostring(data.path) }):fg 'blue') end

    -- 提取程序
    if data.program then
      table.insert(lines, lc.style.line({ '⚙️ Program: ', tostring(data.program) }):fg 'green')
    end

    -- 提取参数
    if data.arguments then
      local args = data.arguments
      if type(args) == 'table' then
        table.insert(lines, lc.style.line({ '📝 Arguments: ', table.concat(args, ' ') }):fg 'green')
      else
        table.insert(lines, lc.style.line({ '📝 Arguments: ', tostring(args) }):fg 'green')
      end
    end

    -- 提取运行次数
    if data.runs then table.insert(lines, lc.style.line({ '🔄 Runs: ', tostring(data.runs) }):fg 'blue') end

    -- 提取上次退出码
    if data['last exit code'] then
      local exit_code = tostring(data['last exit code'])
      local exit_color = (exit_code == '0' or exit_code == '(never exited)') and 'green' or 'red'
      table.insert(lines, lc.style.line({ '🚪 Last Exit Code: ', exit_code }):fg(exit_color))
    end

    -- 提取 spawn type
    if data['spawn type'] then
      table.insert(lines, lc.style.line({ '🎯 Spawn Type: ', tostring(data['spawn type']) }):fg 'yellow')
    end

    -- 提取 properties
    if data.properties then
      local props = data.properties
      if type(props) == 'table' then
        local prop_list = {}
        for k, v in pairs(props) do
          table.insert(prop_list, tostring(k))
        end
        if #prop_list > 0 then
          table.insert(lines, lc.style.line({ '⚡ Properties: ', table.concat(prop_list, ' | ') }):fg 'magenta')
        end
      else
        table.insert(lines, lc.style.line({ '⚡ Properties: ', tostring(props) }):fg 'magenta')
      end
    end

    -- 对齐列
    lc.style.align_columns(lines)

    -- 转换为文本
    cb(lc.style.text(lines))
  end)
end

return M
