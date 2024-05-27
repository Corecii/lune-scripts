--[=[ lunar
about = """Installs wally packages, with types and patches.
Requires wally, wally-package-types, wally-patch-package, and rojo."""
]=]

local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local function exec_raw(cmdline: string | { string }, options)
	local pieces
	if type(cmdline) == "string" then
		pieces = {}
		for piece in string.gmatch(" " .. cmdline, "%s+([^%s]+)") do
			table.insert(pieces, piece)
		end
	else
		pieces = cmdline
	end

	local program = table.remove(pieces, 1)
	assert(program ~= nil, "cmdline must include a program")
	local result = process.spawn(program, pieces, options)
	return result
end

local function exec(cmdline: string | { string })
	local result = exec_raw(cmdline, { stdio = "inherit" })
	if not result.ok then
		process.exit(result.code)
	end
end

exec("wally install")

local projectFile
if fs.isFile(".vscode/settings.json") then
	local data = serde.decode("json", fs.readFile(".vscode/settings.json"))
	projectFile = data["luau-lsp.sourcemap.rojoProjectFile"]
end

projectFile = projectFile or "default.project.json"

local updatedSourcemap = false
if fs.isFile(projectFile) then
	exec({ "rojo", "sourcemap", "-o", "sourcemap.json", projectFile })
	updatedSourcemap = true
end

if exec_raw("wally-package-types --version").ok and updatedSourcemap then
	if fs.isDir("Packages") then
		exec("wally-package-types --sourcemap sourcemap.json ./Packages/")
	end
	if fs.isDir("ServerPackages") then
		exec("wally-package-types --sourcemap sourcemap.json ./ServerPackages/")
	end
	if fs.isDir("DevPackages") then
		exec("wally-package-types --sourcemap sourcemap.json ./DevPackages/")
	end
end

if exec_raw("wally-patch-package --version").ok then
	exec("wally-patch-package")
end
