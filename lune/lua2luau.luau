--[=[ lunar
	about = "Converts all lua files to luau files in the target directory"
	args = "<target>"
]=]

local process = require("@lune/process")
local fs = require("@lune/fs")

local target = process.args[1]

if not target or target == "" then
	print("Usage: lune run lua2luau <target>")
	return
end

local fixFile, fixDir

local function fixUnknown(path: string)
	if fs.isDir(path) then
		fixDir(path)
	else
		fixFile(path)
	end
end

function fixFile(path: string)
	if not path:match("%.lua$") then
		return
	end

	fs.move(path, (path:gsub("%.lua$", ".luau")))
end

function fixDir(path: string)
	for _, file in fs.readDir(path) do
		fixUnknown(`{path}/{file}`)
	end
end

fixUnknown(target)
