--[=[ lunar
about = "Installs wally packages, with types and patches."
]=]

local fs = require("@lune/fs")

local exec = require("./lib/exec")
local getProjectFile = require("./lib/getProjectFile")

exec({ "wally", "install" }):assert()

if exec({ "rojo", "--version" }).ok then
	local projectFile = getProjectFile()
	
	local updatedSourcemap = false
	if projectFile then
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
