--[=[ lunar
	hide = true
]=]

local fs = require("@lune/fs")
local serde = require("@lune/serde")
local exec = require("./exec")

return function()
	print("Reading tasks file...")
	local tasksFile = serde.decode("json", fs.readFile(".vscode/tasks.json"))

	for index, task in tasksFile.tasks do
		if task.label:match("lunar[ %-]") or task.isLunarTask then
			tasksFile.tasks[index] = nil
		end
	end

	print("Reading `lunar help` output...")
	local lunarOutput = exec({ "lunar", "help" }, {
		stdio = "default",
	}):assert().stdout

	local commandsSection = "\n" .. assert(lunarOutput:match("\nCommands:\r*\n([%s%S]-)%s*\r*\nOptions:"))
	assert(commandsSection)

	print("Collecting tasks...")
	local start = 1
	while true do
		local matchStart, matchEnd = commandsSection:find("\n  %S+[^%S\r\n]*", start)
		if not matchStart or not matchEnd then
			break
		end
		start = matchEnd

		local preSpaces = matchEnd - matchStart

		local command = commandsSection:sub(matchStart, matchEnd):match("%s+(%S+)%s*")
		assert(command)
		local about

		if command == "help" then
			continue
		end

		local nextMatchStart = commandsSection:find("\n  %S+%s*", matchEnd + 1)
		if nextMatchStart then
			about = commandsSection:sub(matchEnd + 1, nextMatchStart - 1)
		else
			about = commandsSection:sub(matchEnd + 1)
		end
		about = about:gsub("\r*\n([^\r\n]*)", function(line)
			return "\n" .. line:sub(preSpaces)
		end)
		about = assert(about:match("^[\r\n]*(.*)[\r\n]*$"))

		table.insert(tasksFile.tasks, {
			label = command,
			type = "shell",
			command = `lunar {command}`,
			presentation = {
				reveal = "always",
				panel = "dedicated",
				clear = true,
			},

			isLunarTask = true,
		})

		print("  collected", command)
	end

	print("Writing tasks file...")
	fs.writeFile(".vscode/tasks.json", serde.encode("json", tasksFile, true))

	print("Done!")
end
