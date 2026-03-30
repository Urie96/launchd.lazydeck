local config = require 'launchd.config'
local meta = require 'launchd.meta'

local M = {}

local function info_entry(key, message, detail, color)
  return {
    key = key,
    kind = 'info',
    title = 'launchd',
    message = message,
    detail = detail,
    color = color or 'darkgray',
    display = lc.style.line {
      lc.style.span(message):fg(color or 'darkgray'),
    },
  }
end

local function status_color(category)
  if category == 'running' then return 'green' end
  if category == 'failed' then return 'yellow' end
  return 'darkgray'
end

local function service_entry(label, pid, status, category)
  return {
    key = label,
    kind = 'service',
    label = label,
    pid = pid,
    status = status,
    category = category,
    domain = config.get().domain,
    display = lc.style.line {
      lc.style.span(label):fg(status_color(category)),
    },
  }
end

function M.setup(opt)
  config.setup(opt or {})
  meta.setup(config.get())
end

function M.list(_, cb)
  lc.system({ config.get().command, 'list' }, function(out)
    if out.code ~= 0 then
      lc.log('error', 'Failed to list services: {}', out.stderr or 'Unknown error')
      cb(meta.attach {
        info_entry('error', 'Failed to list services', out.stderr or 'Unknown error', 'red'),
      })
      return
    end

    local entries = {}
    local lines = out.stdout:split '\n'
    for i, raw in ipairs(lines) do
      if i == 1 or raw:trim() == '' or raw:match '^PID' then goto continue end

      local parts = raw:gsub('%s+', ' '):trim():split ' '
      if #parts >= 3 then
        local pid = parts[1]
        local status = parts[2]
        local label = parts[3]

        local category = 'stopped'
        if pid ~= '-' then
          category = 'running'
        elseif status ~= '0' then
          category = 'failed'
        end

        table.insert(entries, service_entry(label, pid, status, category))
      end

      ::continue::
    end

    if #entries == 0 then
      cb(meta.attach {
        info_entry('empty', 'No launchd services found', 'Check domain or launchctl permissions.', 'yellow'),
      })
      return
    end

    cb(meta.attach(entries))
  end)
end

return M
