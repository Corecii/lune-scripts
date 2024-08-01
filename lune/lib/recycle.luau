local process = require("@lune/process")
local stdio = require("@lune/stdio")

local exec = require("./exec")
local platform = require("./platform")

return function(file_in: string)
	if platform ~= "windows" then
		-- TODO: implement deletion for other platforms!
		-- In the meantime, we'll just ask the user for confirmation.
		local ok = stdio.prompt("confirm", `{stdio.color("red")}Permanently delete {file_in}?{stdio.color("reset")}`)
		if not ok then
			print(`{stdio.color("yellow")}User cancelled; exiting...{stdio.color("reset")}`)
			process.exit(1)
		end
	end
	
	local cwd = process.cwd:gsub("/", "\\"):gsub("\\$", "")
	local file = file_in:gsub("/", "\\")
	local fullPath
	if file:match("^%w+:\\") or file:match("^\\\\") then
		fullPath = file
	else
		fullPath = cwd .. "\\" .. file
	end

	return exec({
		"powershell",
	}, {
		stdin = `cd "{process.cwd}";`
			.. '$sh = new-object -comobject "Shell.Application";'
			.. `$ns = $sh.Namespace(0).ParseName("{fullPath}");`
			.. '$ns.InvokeVerb("delete");',
		stdio = {
			stdout = "none",
			stderr = "none",
		},
	})
end
