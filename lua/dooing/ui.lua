---@diagnostic disable: undefined-global, param-type-mismatch, deprecated
-- UI Module for Dooing Plugin - Compatibility wrapper
-- This file maintains backward compatibility while delegating to the new modular structure

-- Simply require and return the new modular UI
return require("dooing.ui.init")
