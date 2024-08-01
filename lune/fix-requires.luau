--[=[ lunar

	about = "Fixes broken requires due to moving files or missing imports"
	args = "[-y --non-interactive]"
]=]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local net = require("@lune/net")
local process = require("@lune/process")
local exec = require("./lib/exec")
local getProjectFile = require("./lib/getProjectFile")

local NON_INTERACTIVE = table.find(process.args, "-y") or table.find(process.args, "--non-interactive")

type Item = {
	name: string,
	parent: Item?,
	children: { [string]: { [Item]: boolean } },
	sourcemap: any?,
}

local newTypesResult
local ok, _err = pcall(function()
	newTypesResult =
		net.request("https://raw.githubusercontent.com/JohnnyMorganz/luau-lsp/main/scripts/globalTypes.d.luau")
end)

if not ok or not newTypesResult or not newTypesResult.ok then
	if not fs.metadata("globalTypes.d.luau").exists then
		warn(
			"Failed to download Roblox API types, and none are already downloaded. Can't run Luau analysis safely. Cancelling."
		)
		process.exit(1)
	else
		warn("Failed to download Roblox API types, using cached types. These may be outdated.")
	end
else
	fs.writeFile("globalTypes.d.luau", newTypesResult.body)
end

local projectFile = getProjectFile()

exec(
	{ "rojo", "sourcemap", "-o", "sourcemap.json", projectFile }
):assert()

local function withStyle(styles: string, text: string)
	local result = {}
	for _, style in string.split(styles, " ") do
		if style == "bold" or style == "dim" then
			table.insert(result, stdio.style(style))
		elseif style == "reset" then
			table.insert(result, stdio.style("reset"))
			table.insert(result, stdio.color("reset"))
		else
			table.insert(result, stdio.color(style :: any))
		end
	end

	return table.concat(result, "") .. text .. stdio.style("reset") .. stdio.color("reset")
end

local sourcemapJson = serde.decode("json", fs.readFile("sourcemap.json"))

local globalItemsByName: { [string]: { [Item]: boolean } } = {}
local globalItemsByPath: { [string]: { [Item]: boolean } } = {}

local NO_INDEX = {
	["_Index"] = true,
}

local function normalizePath(path: string)
	return path:gsub("[/\\]+", "/"):gsub("%./", "")
end

local function processSourcemap(sourcemapItems: { any }, parent: Item?)
	for _, sourcemap in sourcemapItems do
		if NO_INDEX[sourcemap.name] then
			continue
		end

		local item = {
			name = sourcemap.name,
			sourcemap = sourcemap,
			parent = parent,
			children = {},
		}

		if parent then
			if not parent.children[sourcemap.name] then
				parent.children[sourcemap.name] = {}
			end

			parent.children[sourcemap.name][item] = true
		end

		if not globalItemsByName[item.name] then
			globalItemsByName[item.name] = {}
		end

		globalItemsByName[item.name][item] = true

		for _, path in sourcemap.filePaths or {} do
			path = normalizePath(path)
			if not globalItemsByPath[path] then
				globalItemsByPath[path] = {}
			end

			globalItemsByPath[path][item] = true
		end

		if sourcemap.children then
			processSourcemap(sourcemap.children, item)
		end
	end
end

local root = {
	name = "root",
	children = {},
	sourcemap = sourcemapJson,
}

processSourcemap(sourcemapJson.children, root)

local function buildShortestPath(from: Item, to: Item): string?
	local toAncestors = {}
	local toProc: Item? = to
	while toProc do
		toAncestors[toProc] = true
		toProc = toProc.parent
	end

	local sharedAncestor: Item? = nil
	local fromProc: Item? = from
	local fromPath = { "script" }
	while fromProc do
		if toAncestors[fromProc] then
			sharedAncestor = fromProc
			break
		end
		table.insert(fromPath, "Parent")
		fromProc = fromProc.parent
	end

	if not sharedAncestor then
		return nil
	end

	local toPath = {}
	toProc = to
	while toProc and toProc ~= sharedAncestor do
		table.insert(toPath, 1, toProc.name)
		toProc = toProc.parent
	end

	return table.concat(fromPath, ".") .. "." .. table.concat(toPath, ".")
end

local function countSet(set: { [any]: any })
	local count = 0
	for _ in set do
		count += 1
	end

	return count
end

local result = exec({
	"luau-lsp", "analyze", "--sourcemap", "sourcemap.json", "--settings", ".vscode/settings.default.json", "--ignore", ':Packages/**,ServerPackages/**"', "--defs", "globalTypes.d.luau", "--base-luaurc", ".luaurc", "--formatter", "gnu", "game/modules",
})

local entries = {}

local last
for i, line in string.split(result.stderr, "\n") do
	line = line:gsub("\r*$", "")

	local file, lineStart, colStart, lineEnd, colEnd, err =
		string.match(line, "([^:]*%.luau?) ?[^:]*:(%d+)%.(%d+)%-(%d+)%.(%d+): (.*)")
	if file then
		if file:match("^%w*Packages") then
			continue
		end
		assert(lineStart and colStart and lineEnd and colEnd and err)
		if last then
			last.err = table.concat(last.errLines, "\n")
		end

		last = {
			file = file,
			lineStart = assert(tonumber(lineStart)),
			colStart = assert(tonumber(colStart)),
			lineEnd = assert(tonumber(lineEnd)),
			colEnd = assert(tonumber(colEnd)),

			err = err,
			errLines = { err },
		}
		table.insert(entries, last)
	elseif last then
		table.insert(last.errLines, line)
	end
end

if last then
	last.err = table.concat(last.errLines, "\n")
end

local function buildLineColsPattern(lineStart: number, colStart: number, lineEnd: number, colEnd: number)
	local preLines = string.rep("[^\r\n]*\r*\n", lineStart - 1)
	local preCols = string.rep(".", colStart - 1)

	if lineStart == lineEnd then
		local cols = string.rep(".", colEnd - colStart + 1)
		return `^({preLines}{preCols})({cols})`
	else
		local midLines = string.rep(".*\r*\n", lineEnd - lineStart - 1)
		local finalLineCols = string.rep(".", colEnd)
		return `^({preLines}{preCols})([^\r\n]*\r*\n{midLines}{finalLineCols})`
	end
end

local function readLineCols(
	file: string,
	info: { lineStart: number, colStart: number, lineEnd: number, colEnd: number }
)
	local _pre, selection =
		string.match(file, buildLineColsPattern(info.lineStart, info.colStart, info.lineEnd, info.colEnd))
	return selection
end
local function replaceLineCols(
	file: string,
	info: { lineStart: number, colStart: number, lineEnd: number, colEnd: number },
	replacement
)
	return (
		string.gsub(file, buildLineColsPattern(info.lineStart, info.colStart, info.lineEnd, info.colEnd), replacement)
	)
end

for _, entry in entries do
	if entry.err:match("TypeError: Unknown require:") then
		local contents = fs.readFile(entry.file)
		local requireExpr = readLineCols(contents, entry)
		if not requireExpr then
			warn("Could not find lines for", entry)
			continue
		end

		local targetFile = requireExpr:match("%.([^%.]*)%s*%)%s*$")
		if not targetFile then
			warn(`Could not find target file for {requireExpr} in {entry.file}`)
			continue
		end

		local targetItems = globalItemsByName[targetFile]
		if not targetItems then
			warn(`No item found for file {targetFile}, skipping...`)
			continue
		end
		if countSet(targetItems) > 1 then
			warn(`Multiple target items for {targetFile}, using the first one...`)
		end
		local targetItem = assert((next(targetItems)))

		local thisPath = normalizePath(entry.file)
		local thisItems = globalItemsByPath[thisPath]
		if not thisItems then
			warn(`No item found for path {thisPath}, skipping...`)
			continue
		end
		if countSet(thisItems) > 1 then
			warn(`Multiple this items for {thisPath}, using the first one...`)
		end
		local thisItem = assert((next(thisItems)))

		local thisShortestPath = buildShortestPath(thisItem, targetItem)
		if not thisShortestPath then
			warn(`Could not find shortest path between {thisItem.name} and {targetItem.name}, skipping...`)
			continue
		end

		local filename = normalizePath(entry.file):match("[^/]*$") or "<unknown>"

		if
			NON_INTERACTIVE
			or stdio.prompt(
				"confirm",
				stdio.style("reset")
					.. "Replace broken require to "
					.. withStyle("bold blue", targetFile)
					.. " in "
					.. withStyle("bold blue", filename)
					.. "? "
			)
		then
			fs.writeFile(entry.file, replaceLineCols(contents, entry, `%1require({thisShortestPath})`))
		end
	elseif entry.err:match("TypeError: Unknown global") then
		local contents = fs.readFile(entry.file)
		local reference = readLineCols(contents, entry)

		local targetItems = globalItemsByName[reference]
		if not targetItems then
			warn(`No item found for {reference}, skipping...`)
			continue
		end
		if countSet(targetItems) > 1 then
			warn(`Multiple target items for {reference}, using the first one...`)
		end
		local targetItem = assert((next(targetItems)))

		local thisPath = normalizePath(entry.file)
		local thisItems = globalItemsByPath[thisPath]
		if not thisItems then
			warn(`No item found for path {thisPath}, skipping...`)
			continue
		end
		if countSet(thisItems) > 1 then
			warn(`Multiple this items for {thisPath}, using the first one...`)
		end
		local thisItem = assert((next(thisItems)))

		local thisShortestPath = buildShortestPath(thisItem, targetItem)
		if not thisShortestPath then
			warn(`Could not find shortest path between {thisItem.name} and {targetItem.name}, skipping...`)
			continue
		end

		local filename = normalizePath(entry.file):match("[^/]*$") or "<unknown>"

		if
			NON_INTERACTIVE
			or stdio.prompt(
				"confirm",
				stdio.style("reset")
					.. "Add import for "
					.. withStyle("bold blue", reference)
					.. " in "
					.. withStyle("bold blue", filename)
					.. "? "
			)
		then
			local import = `local {reference} = require({thisShortestPath})\n`

			local existingRequire = string.find(contents, "\n[^\n]require%(", 1)
			if existingRequire then
				contents = string.gsub(contents, "\n([^\n]require%()", `\n{import}%1`)
			else
				contents = import .. contents
			end

			fs.writeFile(entry.file, contents)
		end
	end
end

print(withStyle("bold green", "Done fixing requires."))
