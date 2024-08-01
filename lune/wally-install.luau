--[=[ lunar
about = "Installs wally packages, with types and patches."
]=]

local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")

local exec = require("./lib/exec")

exec({ "wally", "install" }):assert()

if exec({ "rojo", "--version" }).ok then
	local projectFile
	if fs.isFile(".vscode/settings.json") then
		local data = serde.decode("json", fs.readFile(".vscode/settings.json"))
		projectFile = data["luau-lsp.sourcemap.rojoProjectFile"]
	end

	projectFile = projectFile or "default.project.json"

	local updatedSourcemap = false
	if fs.isFile(projectFile) then
		exec({ "rojo", "sourcemap", "-o", "sourcemap.json", projectFile }):assert()
		updatedSourcemap = true
	end

	if exec({ "wally-package-types", "--version" }).ok and updatedSourcemap then
		if fs.isDir("Packages") then
			exec({ "wally-package-types", "--sourcemap", "sourcemap.json", "./Packages/" }):assert()
		end
		if fs.isDir("ServerPackages") then
			exec({ "wally-package-types", "--sourcemap", "sourcemap.json", "./ServerPackages/" }):assert()
		end
		if fs.isDir("DevPackages") then
			exec({ "wally-package-types", "--sourcemap", "sourcemap.json", "./DevPackages/" }):assert()
		end
	end

	if exec({ "wally-patch-package", "--version" }).ok then
		exec({ "wally-patch-package" }):assert()
	end
end
