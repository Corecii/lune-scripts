--[=[ lunar
	hide = true
]=]

local fs = require("@lune/fs")
local exec = require("./lib/exec")
local refreshVsCodeTasks = require("./lib/refreshVsCodeTasks")
local getProjectFile = require("./lib/getProjectFile")

print("Trusting Lunar scripts...")
exec({ "lunar", "--trust-new", "help" }, { stdio = "default" }):assert()
print("")

print("Setting up Lune editor environment...")
exec({ "lune", "setup" }):assert()
print("")

print("Updating VS Code tasks file to include new Lunar tasks...")
refreshVsCodeTasks()
print("")

if not fs.metadata("Packages").exists then
	print("Installing missing wally packages...")
	exec({ "lunar", "wally-install" }):assert()
end
print("")

local projectFile = getProjectFile()
if projectFile then
	print("Updating sourcemap.json...")
	exec({ "rojo", "sourcemap", "-o", "sourcemap.json", projectFile }):assert()
	print("")
end

print("Project setup done!")
