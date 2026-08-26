local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local IS_SERVER = RunService:IsServer()

local Context = require(script.Context)
local Logger = require(ReplicatedStorage.Packages.Logger)

local loaderLogger: Logger.Logger = Logger.new("Loader")

local Loader = {}
Loader.__index = Loader

local ALLOWED_SUFFIX = if IS_SERVER then "Service" else "Controller"

type ModuleTable = {
	Init: ((self: any) -> ())?,
	Start: ((self: any) -> ())?,
	Get: ((...any) -> any)?,
	GetService: ((name: string) -> LoadedModule?)?,
	[string]: any,
}

export type LoadedModule = Context.ContextWrapper & ModuleTable

local loadedModules: { [string]: LoadedModule } = {}
local moduleOrder: { LoadedModule } = {}
local isBootstrapped = false

--------------------------------------------------------------------------------
-- Helpers
--------------------------------------------------------------------------------

local function isValidModuleName(name: string): boolean
	return string.sub(name, -#ALLOWED_SUFFIX) == ALLOWED_SUFFIX
end

local function loadModule(moduleScript: ModuleScript): LoadedModule?
	if not isValidModuleName(moduleScript.Name) then
		loaderLogger:Info(string.format("Skipping '%s' (Must end with '%s')", moduleScript.Name, ALLOWED_SUFFIX))
		return nil
	end

	if loadedModules[moduleScript.Name] then
		loaderLogger:Error(
			("Duplicate %s '%s' found.\n%s\n%s")
				:format(
					ALLOWED_SUFFIX,
					moduleScript.Name,
					moduleScript:GetFullName(),
					loadedModules[moduleScript.Name].__ModuleScript:GetFullName()
				)
		)
		return loadedModules[moduleScript.Name]
	end

	local success, result = pcall(require, moduleScript)
	if not success then
		loaderLogger:Error(string.format("Failed to require module '%s': %s", moduleScript.Name, tostring(result)))
		return nil
	end

	if type(result) ~= "table" then
		loaderLogger:Warn(string.format("Module '%s' did not return a table; skipping lifecycle.", moduleScript.Name))
		return nil
	end

	-- Preserve feature-owned Get methods. GetService is the collision-free loader lookup;
	-- legacy modules only receive Get when they do not already define one.
	result.GetService = Loader.Get
	if result.Get == nil then
		result.Get = Loader.Get
	end

	local wrapped = Context.wrap(result) :: any

	loadedModules[moduleScript.Name] = wrapped
	table.insert(moduleOrder, wrapped)

	return wrapped
end

local function loadDescendants(container: Instance)
	for _, child in container:GetDescendants() do
		if child:IsA("ModuleScript") and isValidModuleName(child.Name) then
			loadModule(child)
		end
	end
end
--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

--- Retrieves a loaded service or controller by name.
function Loader.Get(name: string)
	local mod = loadedModules[name]

	if not mod then
		loaderLogger:Error(("%s '%s' does not exist!")
			:format(ALLOWED_SUFFIX, name))
	end

	return mod
end

--- Recursively loads descendants, calls :Init() on all, then spawns :Start() on all.
function Loader.Bootstrap(container: Instance): { [string]: LoadedModule }
	local startTime = os.clock()
	
	if isBootstrapped then
		loaderLogger:Warn("Loader.Bootstrap() was called more than once!")
		return loadedModules
	end
	isBootstrapped = true

	local contextName = if IS_SERVER then "Server" else "Client"
	loaderLogger:Info(string.format("Bootstrapping %s %ss...", contextName, ALLOWED_SUFFIX))

	-- Step 1: Recursively require all matching descendants
	loadDescendants(container)

	-- Step 2: Init Phase (Sequential)
	for _, mod in moduleOrder do
		if type(mod.Init) == "function" then
			local success, err = xpcall(function()
				mod:Init()
			end, debug.traceback)

			if not success then
				loaderLogger:Error(("Error during :Init() step:\n%s"):format(tostring(err)))
			end
		end
	end

	-- Step 3: Start Phase (Asynchronous spawn)
	for _, mod in moduleOrder do
		if type(mod.Start) == "function" then
			task.spawn(function()
				local success, err = xpcall(function()
					mod:Start()
				end, debug.traceback)

				if not success then
					loaderLogger:Error(("Error during :Start():\n%s"):format(err))
				end
			end)
		end
	end

	loaderLogger:Info(string.format("Successfully bootstrapped %d modules in %s seconds", #moduleOrder, os.clock() - startTime))
	return loadedModules
end

return Loader
