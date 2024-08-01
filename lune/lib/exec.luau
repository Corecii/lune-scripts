local process = require("@lune/process")

local resultMeta = {}
resultMeta.__index = resultMeta

export type ExecResult = typeof(setmetatable({} :: process.SpawnResult, resultMeta))

function resultMeta.assert(self: ExecResult): ExecResult
	if not self.ok then
		warn(`Command failed:\n{self.stderr}\n{self.stdout}`)
		process.exit(self.code)
	end

	return self
end

local function exec(cmd: { string }, options: process.SpawnOptions?)
	local bin = cmd[1]
	local args = table.clone(cmd)
	table.remove(args, 1)

	local options: process.SpawnOptions = options and table.clone(options) or {}

	if options.shell == false then
		options.shell = nil
	elseif options.shell == nil then
		options.shell = true
	end

	local result = process.spawn(bin, args, options)
	result = table.clone(result)
	setmetatable(result, resultMeta)

	return result
end

return exec
