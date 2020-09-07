local json = {}
local string = string
local sformat = string.format
local sbyte = string.byte
local tconcat = table.concat
local mhuge = math.huge
local rawget = rawget
local next = next
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local type = type

local stepIgnore = __DebugAdapter and __DebugAdapter.stepIgnore or function(f) return f end

local function encode_nil()
  return "null"
end
stepIgnore(encode_nil)

local escape_char_map = {
  [ "\\" ] = "\\\\", [ "\"" ] = "\\\"", [ "\b" ] = "\\b",
  [ "\f" ] = "\\f", [ "\n" ] = "\\n", [ "\r" ] = "\\r",
  [ "\t" ] = "\\t", }
local function escape_char(c)
  return escape_char_map[c] or sformat("\\u%04x", sbyte(c))
end
stepIgnore(escape_char)

local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end
stepIgnore(encode_string)

local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val then
    return [["NaN"]]
  elseif val <= -mhuge then
    return [["-Infinity"]]
  elseif val >= mhuge then
    return [["Infinity"]]
  else
    return sformat("%.14g", val)
  end
end
stepIgnore(encode_number)

local encode;

local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then return [["<circular>"]] end

  stack[val] = true

  local is_array = false
  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    is_array = true
    local n = 1
    for k,v in pairs(val) do
      if k ~= n then
        is_array = false
        break
      end
      res[k] = encode(v, stack)
      n = n + 1
    end
  end

  if is_array then
    -- Encode
    stack[val] = nil
    return "[" .. tconcat(res, ",") .. "]"
  else
    -- Treat as an object
    local i = 1
    for k, v in pairs(val) do
      res[i] = encode(tostring(k), stack) .. ":" .. encode(v, stack)
      i = i + 1
    end
    stack[val] = nil
    return "{" .. tconcat(res, ",") .. "}"
  end
end
stepIgnore(encode_table)

local type_encode = {
  ["nil"] = encode_nil,
  ["string"] = encode_string,
  ["table"] = encode_table,
  ["boolean"] = tostring,
  ["number"] = encode_number,
}

function encode(value, stack)
  local t = type(value)
  local f = type_encode[t]
  if f then
    return f(value, stack)
  else
    return '"<'..t..'>"'
  end
end
stepIgnore(encode)

json.encode = encode
return json