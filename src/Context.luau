local RunService = game:GetService("RunService")

local Context = {}
Context.__index = Context

local IS_SERVER = RunService:IsServer()

type Callback = (...any) -> ...any

export type ContextWrapper = {
	server: (self: ContextWrapper, callback: Callback) -> ContextWrapper,
	client: (self: ContextWrapper, callback: Callback) -> ContextWrapper,
	[string]: any,
}

--- Wraps a target table so `.server()` and `.client()` can be chained on it.
function Context.wrap(target: { [string]: any }): ContextWrapper
	local self = setmetatable({
		_target = target,
	}, Context)

	return (self :: any) :: ContextWrapper
end

--- Executes the callback only if running on the Server.
function Context:server(callback: Callback): ContextWrapper
	if IS_SERVER then
		callback(self._target)
	end
	return self
end

--- Executes the callback only if running on the Client.
function Context:client(callback: Callback): ContextWrapper
	if not IS_SERVER then
		callback(self._target)
	end
	return self
end

-- Fallback to access underlying properties on the original module
function Context:__index(key: any): any
	local raw = rawget(Context, key)
	if raw ~= nil then
		return raw
	end

	local target = rawget(self, "_target")
	if type(target) == "table" then
		return target[key]
	end

	return nil
end

-- Preserve singleton state when loader lifecycle methods receive a wrapper as self.
function Context:__newindex(key: any, value: any)
	local target = rawget(self, "_target")
	if type(target) == "table" then
		target[key] = value
		return
	end

	rawset(self, key, value)
end

return Context
