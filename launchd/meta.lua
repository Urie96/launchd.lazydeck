local action = require 'launchd.action'

local M = {}

local function add_keymap(targets, key, callback, desc)
  if not key or key == '' then return end
  for _, target in ipairs(targets) do
    target[key] = { callback = callback, desc = desc }
  end
end

local metas = {
  service = {
    __index = {
      keymap = {},
      preview = function(entry, cb)
        action.preview_service(entry, cb)
      end,
    },
  },
  info = {
    __index = {
      keymap = {},
      preview = function(entry, cb)
        cb(action.preview_info(entry))
      end,
    },
  },
}

function M.setup(cfg)
  local keymap = (cfg or {}).keymap or {}
  local service_map = metas.service.__index.keymap

  for key, _ in pairs(service_map) do
    service_map[key] = nil
  end

  add_keymap({ service_map }, keymap.action, action.select_action, 'service actions')
  add_keymap({ service_map }, keymap.start, action.start, 'start service')
  add_keymap({ service_map }, keymap.stop, action.stop, 'stop service')
  add_keymap({ service_map }, keymap.enable, action.enable, 'enable service')
  add_keymap({ service_map }, keymap.disable, action.disable, 'disable service')
  add_keymap({ service_map }, keymap.bootout, action.bootout, 'bootout service')
  add_keymap({ service_map }, keymap.kill, action.kill, 'kill service')
  add_keymap({ service_map }, keymap.kill9, action.kill9, 'kill service with SIGKILL')
end

function M.attach(entries)
  for i, entry in ipairs(entries or {}) do
    local mt = metas[entry.kind]
    if mt then entries[i] = setmetatable(entry, mt) end
  end
  return entries
end

return M
