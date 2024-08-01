local fs = require("@lune/fs")
local serde = require("@lune/serde")

return function()
	local projectFile
	if fs.isFile(".vscode/settings.json") then
		local data
		pcall(function()
			-- VS Code's json files are technically either json5 or json with
			-- comments, so decode might fail!
			data = serde.decode("json", fs.readFile(".vscode/settings.json"))
		end)
		if data then
			projectFile = data["luau-lsp.sourcemap.rojoProjectFile"]
		end
	end

	projectFile = projectFile or "default.project.json"

	if fs.isFile(projectFile) then
		return projectFile
	else
		return nil
	end
end