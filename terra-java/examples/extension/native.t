local J = require "terra-java"

local ext = J.package("terrajava.examples.extension")
local Accumulator = ext.Accumulator

-- Return values and Java method interop.
terra Accumulator:isPos() : J.boolean
  return [J.boolean](self:sign() == 1.0)
end

-- C interop.
local C = terralib.includec("math.h")
terra Accumulator:sqrt()
  self:value(C.sqrt(self:value()))
end

-- Parameters and overloading.
Accumulator.methods.add = terralib.overloadedfunction("add", {
  terra(self : Accumulator, x : J.int)
    self:add([double](x))
  end,
  terra(self : Accumulator, x : J.double)
    self:value(self:value() + x)
  end
})

J.savelib("./obj", ext)

-- XXX Do stuff with the extension.
