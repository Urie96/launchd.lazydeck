local M = {}

local function current_uid()
  local handle = io.popen 'id -u'
  if not handle then return '501' end
  local uid = handle:read '*a'
  handle:close()
  return tostring(uid or ''):gsub('%s+', '') ~= '' and tostring(uid):gsub('%s+', '') or '501'
end

local function default_domain()
  local uid = current_uid()
  if uid == '0' then return 'system' end
  return 'gui/' .. uid
end

local cfg = {
  command = 'launchctl',
  domain = default_domain(),
  keymap = {
    action = '<enter>',
    start = 'r',
    stop = 'x',
    enable = 'e',
    disable = 'd',
    bootout = 'b',
    kill = 'k',
    kill9 = 'K',
  },
}

function M.setup(opt)
  cfg = deck.tbl_deep_extend('force', cfg, opt or {})
end

function M.get() return cfg end

return M
