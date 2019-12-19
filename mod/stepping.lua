--this has to be defined before requiring other files so they can mark functions as ignored
local stepIgnoreFuncs = {}
---@param f function
function __DebugAdapter.stepIgnore(f)
  stepIgnoreFuncs[f] = true
end

local variables = require("__debugadapter__/variables.lua")
local normalizeLuaSource = require("__debugadapter__/normalizeLuaSource.lua")

local breakpoints = {}
local stepmode = nil
local stepdepth = 0

function __DebugAdapter.attach()
  local getinfo = debug.getinfo
  local sub = string.sub
  local format = string.format
  local debugprompt = debug.debug
  debug.sethook(function(event,line)
    local ignored = stepIgnoreFuncs[getinfo(2,"f").func]
    if ignored then return end
    if event == "line" then
      local s = getinfo(2,"S").source
      -- startup logging gets all the serpent loads of `global`
      -- serpent itself will also always show up as one of these
      if sub(s,1,1) == "@" then
        s = normalizeLuaSource(s)
        if stepmode == "in" or stepmode == "next" or (stepmode == "over" and stepdepth==0) then
          stepmode = nil
          print(format("DBG: step %s:%d", s, line))
          debugprompt()
        else
          local filebreaks = breakpoints[s]
          if filebreaks then
            local b = filebreaks[line]
            if b == true then
              if (stepmode == "over") then
                stepmode = nil
                stepdepth = 0
              end
              print(format("DBG: breakpoint %s:%d", s, line))
              debugprompt()
            elseif type(b) == "string" then
              -- parse and print logMessage as an expression in the scope of the breakpoint
              -- 0 is getinfo, 1 is sethook callback, 2 is at breakpoint
              local frameId = 3
              local result = __DebugAdapter.stringInterp(b,frameId,nil,"logpoint")
              local varresult = variables.create(nil,result)
              local logpoint = {
                output = varresult.value,
                variablesReference = varresult.variablesReference,
                filePath = s,
                line = line,
              }
              print("DBGlogpoint: " .. game.table_to_json(logpoint))
            end
          end
        end
        -- cleanup variablesReferences
        variables.clear()
      end
    --ignore "tail call" since it's just one of each
    elseif event == "call" then
      local s = getinfo(2,"S").source
      if sub(s,1,1) == "@" then
        s = normalizeLuaSource(s)
        if stepmode == "over" or stepmode == "out" then
          stepdepth = stepdepth + 1
        end
      end
    elseif event == "return" then
      local s = getinfo(2,"S").source
      if sub(s,1,1) == "@" then
        s = normalizeLuaSource(s)
        if stepmode == "over" then
          stepdepth = stepdepth - 1
        elseif stepmode == "out" then
          if stepdepth == 0 then
            stepmode = "next"
          end
          stepdepth = stepdepth - 1
        end
      end
    end
  end,"clr")
end

function __DebugAdapter.detach()
  debug.sethook()
end

---@param source string
---@param breaks SourceBreakpoint[]
---@return Breakpoint[]
function __DebugAdapter.setBreakpoints(source,breaks)
  if breaks then
    local filebreaks = {}
    breakpoints[source] = filebreaks
    for _,bp in pairs(breaks) do
      filebreaks[bp.line] = bp.logMessage or true
    end
  else
    breakpoints[source] = nil
  end
end

---@param steptype string "remote"*("next" | "in" | "over" | "out")
---@param silent nil | boolean
function __DebugAdapter.step(steptype,silent)
  stepmode = steptype
  if stepmode == "over" and stepdepth ~= 0 then
    print(("over with existing depth! %d"):format(stepdepth))
  end
  if not silent then
    print("DBGstep")
  end
end
__DebugAdapter.stepIgnore(__DebugAdapter.step)

---@return string "remote"*("next" | "in" | "over" | "out")
function __DebugAdapter.currentStep()
  return stepmode
end
__DebugAdapter.stepIgnore(__DebugAdapter.currentStep)
