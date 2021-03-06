-- This file generates JNI extension libraries from Terra methods.

local jni = require "terra-java/jni"
local jvm = require "terra-java/jvm"
local util = require "terra-java/util"
local declare = require "terra-java/declare"
local jtypes = require "terra-java/types"

local ENV = jvm.ENV

local P = {}

local function mangle(s)
  --TODO: Escape non-ascii characters as _0XXXX
  return s:gsub("[.]", "/")
          :gsub("_", "_1")
          :gsub(";", "_2")
          :gsub("[[]", "_3")
          :gsub("/", "_")
end

local function export(f)
  local params = {}
  local wrapped = {}
  for i, param in ipairs(f.definition.parameters) do
    local sym = symbol(jtypes.jni_type(param.type), param.name)
    table.insert(params, sym)
    table.insert(wrapped, `declare.wrap([param.type], [sym]))
  end
  return terra(env : &jni.Env, [params])
    var [ENV] = jvm.Env{env}
    return declare.unwrap(f(wrapped))
  end
end

function P.exports(package)

  local exports = {}

  terra exports.JNI_OnLoad(vm : &jni.VM, reserved : &opaque)
    var [ENV]
    var vm = jvm.VM{vm}
    var res = vm:GetEnv([&&opaque](&[ENV].env), jvm.version)
    if res < 0 then
      util.fatal("Error getting JVM during extension load: %d", res)
    end
    [declare.used_inits()]
    return jvm.version
  end

  local pkg = getmetatable(package).name
  for cls, T in pairs(package) do
    local cls_mangled = mangle(tostring(T))

    for name, method in pairs(T.methods) do

      local method_mangled = mangle(name)
      local mangled = "Java_" .. cls_mangled .. "_" .. method_mangled

      -- Un-overload single-signature methods.
      if terralib.type(method) == "overloadedterrafunction" then
        local defs = method:getdefinitions()
        if #defs == 1 then
          method = defs[1]
        end
      end

      -- Export each overload.
      if terralib.type(method) == "overloadedterrafunction" then
        for _, def in ipairs(method:getdefinitions()) do
          if not declare.generated(def) then
            local params = def:gettype().parameters
            -- Exclude self from parameter list.
            if #params > 0 and def.definition.parameters[1].name == "self" then
              params = util.popl(params)
            end
            local sig = mangle(jtypes.jvm_param_sig(params))
            local mangled = mangled .. "__" .. sig
            exports[mangled] = export(def)
          end
        end

      -- Export the only overload.
      elseif terralib.type(method) == "terrafunction" then
        if not declare.generated(method) then
          exports[mangled] = export(method)
        end

      else
        error("Unexpected type of method: " .. terralib.type(method))
      end

    end
  end

  return exports

end

function P.savelib(dirname, name, package)
  local exports = P.exports(package)
  local filename = dirname .. "/lib" .. name .. ".jnilib"
  terralib.saveobj(filename, "sharedlibrary", exports)
end

return P
