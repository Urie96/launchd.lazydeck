local M = {}

local function convert_value(value)
  -- 带引号的字符串
  if value:sub(1, 1) == '"' and value:sub(-1) == '"' then return value:sub(2, -2) end

  -- 布尔值
  if value:lower() == 'true' then
    return true
  elseif value:lower() == 'false' then
    return false
  end

  -- 整数
  if value:match '^%d+$' then return tonumber(value) end

  -- 浮点数
  if value:match '^%d+%.%d+$' then return tonumber(value) end

  -- 数组（逗号分隔）
  if value:find ',' and not value:find '{' then
    local array = {}
    for item in value:gmatch '[^,]+' do
      table.insert(array, convert_value(item:gsub('^%s+', ''):gsub('%s+$', '')))
    end
    return array
  end

  -- 字典（花括号）
  if value:sub(1, 1) == '{' and value:sub(-1) == '}' then
    local dict = {}
    local inner = value:sub(2, -2)
    for pair in inner:gmatch '[^,]+' do
      local k, v = pair:match '([^=]+)=(.+)'
      if k and v then
        k = k:gsub('^%s+', ''):gsub('%s+$', '')
        v = v:gsub('^%s+', ''):gsub('%s+$', '')
        dict[k] = convert_value(v)
      end
    end
    return dict
  end

  -- 默认返回字符串
  return value
end

function M.decode(output)
  -- 使用栈来跟踪嵌套结构
  local stack = {}
  local root = {}
  table.insert(stack, root)

  for line in output:gmatch '[^\r\n]+' do
    local orig_line = line
    line = line:gsub('^%s+', ''):gsub('%s+$', '') -- 去除首尾空白

    -- 跳过空行
    if line == '' then
      -- do nothing
      -- 遇到结束大括号
    elseif line == '}' or line:match '^%s*}%s*$' then
      table.remove(stack)
    -- 匹配数组索引 index = value（必须在键值对之前检查）
    elseif line:match '^%d+%s*=' then
      local index, value = line:match '^(%d+)%s*=%s*(.-)%s*$'
      if index and value then
        if #stack > 0 then
          local num_index = tonumber(index) + 1
          stack[#stack][num_index] = convert_value(value)
        end
      end
    -- 解析键值对：key = value 或 key => value 或 key => {
    elseif line:match '^[^=]+[=]>?' then
      -- 匹配 key = value 或 key => value
      local key, value = line:match '^%s*(.-)%s*=>?%s*(.-)%s*$'
      if key and value then
        -- 处理带引号的键
        key = key:match '^"([^"]+)"$' or key
        key = key:gsub('^%s+', ''):gsub('%s+$', '')

        -- 检查值是否以 { 结尾（开始嵌套对象）
        if value:match '%s*{%s*$' then
          -- 清理可能存在的其他值
          local clean_value = value:gsub('%s*{%s*$', '')
          if clean_value ~= '' then stack[#stack][key] = convert_value(clean_value) end
          -- 创建新的嵌套对象
          stack[#stack][key] = stack[#stack][key] or {}
          table.insert(stack, stack[#stack][key])
        -- 检查值是否以 [ 开头（数组）
        elseif value:match '^%s*%[' then
          stack[#stack][key] = {}
          table.insert(stack, stack[#stack][key])
        else
          -- 普通键值对
          stack[#stack][key] = convert_value(value)
        end
      end
    -- 遇到数组结束符 ]
    elseif line:match '^%s*%]%s*$' then
      if #stack > 1 then table.remove(stack) end
    -- 纯值（数组元素）
    elseif #line > 0 and #stack > 0 then
      local current = stack[#stack]
      if type(current) == 'table' and current ~= root then
        -- 检查是否是数组（连续数字键）
        local is_array = true
        for k in pairs(current) do
          if type(k) ~= 'number' then
            is_array = false
            break
          end
        end
        if is_array or next(current) == nil then
          local index = #current + 1
          current[index] = convert_value(line)
        end
      end
    end
  end

  return root
end

return M
