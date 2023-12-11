--[[
	Wraps `wally install` with type exports in link files.

	Roughly equivalent to wally-package-types, but with support for generics
	with defaults and some support for WaitForChild require paths.
--]]

local process = require("@lune/process")
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local serde = require("@lune/serde")

local result = process.spawn("wally", { "install" }, { stdio = "inherit" })
if not result.ok then
	process.exit(1)
end

print("Fixing package types...")

local genericEqTypes = {
	"^(%b()%s*,)",
	"^(%b{}%s*,)",
	"^(%S+%b<>%s*,)",
	"^(%S+%s*,)",
}

local function parseGenerics(generics: string): { string }
	generics = `{generics},`

	local results = {}

	local cursor = 1
	while true do
		local preTrim = string.match(generics, "^%s*", cursor)
		assert(preTrim)
		cursor += #preTrim

		if #generics - cursor <= 0 then
			break
		end

		local nameWithEq, eq = string.match(generics, "^(%S+)(%s*=%s*)", cursor)
		if nameWithEq and eq then
			table.insert(results, nameWithEq)
			cursor += #nameWithEq
			cursor += #eq

			local matched = false
			for _, genericEq in genericEqTypes do
				local match = string.match(generics, genericEq, cursor)
				if match then
					cursor += #match
					matched = true
					break
				end
			end

			if matched then
				continue
			end
		end

		local name, comma = string.match(generics, "^(%S+)(%s*,)", cursor)
		if name and comma then
			table.insert(results, name)

			cursor += #name
			cursor += #comma

			continue
		end

		warn("Cannot match generics for the following generics:")
		warn(`  {generics}`)
		warn("Value at cursor:")
		warn(`  {string.sub(generics, cursor)}`)
		process.exit(1)
	end

	return results
end

local function collectTypes(path: string): { string }
	local contents = fs.readFile(path)
	local result = {}
	for match in string.gmatch(contents, "export%stype%s([^\n]*)") do
		local name, generics = string.match(match, "^(%S+)(%b<>)")
		if name and generics then
			local genericsInner = string.match(generics, "<(.*)>")
			assert(genericsInner)
			local generics = parseGenerics(genericsInner)
			table.insert(result, `{name}<{table.concat(generics, ", ")}>`)
		else
			table.insert(result, string.match(match, "^(%S+)") :: string)
		end
	end
	return result
end

local function newPathResolver(base)
	return setmetatable({
		__components = { base },
	}, {
		__index = function(self, path): any
			if path == "Parent" then
				table.insert(self.__components, "..")
			elseif path == "WaitForChild" then
				return function(_self: any, childName: string)
					table.insert(self.__components, childName)

					return self
				end
			else
				table.insert(self.__components, path)
			end

			return self
		end,
		__call = function(self)
			return table.concat(self.__components, "/")
		end,
	})
end

local function resolveLinkTargetPath(linkPath: string): string?
	local contents = fs.readFile(linkPath)
	local requireInner = contents:match("return require%((.+)%)")
	if requireInner == nil then
		return nil
	end
	local resolveLine = `local script = ...; return {requireInner}()`
	local resolveFunc = luau.load(resolveLine, {
		debugName = `resolve {linkPath}`,
	})

	return resolveFunc(newPathResolver(linkPath))
end

-- stylua: ignore
local potentialLuauInits = {
	"init.lua", "init.luau",
	"init.server.lua", "init.server.luau",
	"init.client.lua", "init.client.luau",
}

local function getMainLuauPath(path: string): string?
	if fs.isFile(path) then
		return path
	end
	if fs.isFile(`{path}/default.project.json`) then
		local projectContents = fs.readFile(`{path}/default.project.json`)
		local project = serde.decode("json", projectContents)
		if project.tree and project.tree["$path"] then
			return getMainLuauPath(`{path}/{project.tree["$path"]}`)
		end
	end

	for _, init in potentialLuauInits do
		if fs.isFile(`{path}/{init}`) then
			return `{path}/{init}`
		end
	end

	return nil
end

local function rewriteLink(path)
	local contents = fs.readFile(path)
	if string.find(contents, "-- fixed types", 1, true) then
		return
	end

	local linkTargetPath = resolveLinkTargetPath(path)
	if not linkTargetPath then
		warn(`No link target found for {path}`)
		return
	end

	local mainLuauPath = getMainLuauPath(linkTargetPath)
	if not mainLuauPath then
		warn(`No main luau file found for {path}'s link target {linkTargetPath}`)
		return
	end

	local types = collectTypes(mainLuauPath)

	local requireExpression = contents:match("return%s+(require[^\n]+)")
	local newContentsBuilder = {
		"-- fixed types",
		`local LINK = {requireExpression}`,
	}

	for _, item in types do
		table.insert(newContentsBuilder, `export type {item} = LINK.{item}`)
	end

	table.insert(newContentsBuilder, `return LINK`)

	fs.writeFile(path, table.concat(newContentsBuilder, "\n"))
end

for _, name in fs.readDir("Packages") do
	local path = `Packages/{name}`
	if path:find("%.luau?$") and fs.isFile(path) then
		rewriteLink(path)
	end
end

for _, nameOuter in fs.readDir("Packages/_Index") do
	for _, nameInner in fs.readDir(`Packages/_Index/{nameOuter}`) do
		local path = `Packages/_Index/{nameOuter}/{nameInner}`
		if path:find("%.luau?$") and fs.isFile(path) then
			rewriteLink(path)
		end
	end
end

print("  fixed package types")
