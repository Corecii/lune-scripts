--[=[ lunar
	hide = true
	
	[tasks.edit]
		args = ""
		about = "builds the game (to edit.rbxl), launches the Roblox editor, launches Rojo, and syncs back until Roblox is closed."

	[tasks.edit-build]
		args = ""
		about = "builds the game (to edit.rbxl) and launches the Roblox editor"
		
	[tasks.edit-syncback]
		args = ""
		about = "saves the models from the game to the repo"

	[tasks.build]
		args = ""
		about = "builds the game (to build.rbxl)"
]=]

local process = require("@lune/process")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local stdio = require("@lune/stdio")
local task = require("@lune/task")
local DateTime = require("@lune/DateTime")
local net = require("@lune/net")

local exec = require("./exec")
local recycle = require("./recycle")

local function captureRustError(result: exec.ExecResult | { stdout: string, stderr: string }, prefix: string): string
	local output = result.stderr
	output = output:gsub("^.*(%[[^\r\n]*ERROR[^\r\n]*%])", "%1") -- trim everything before the first error
	output = prefix .. string.gsub(output, "\n", "\n" .. prefix) -- indent

	return output
end

local config
if fs.metadata("edit-workflow.toml") then
	config = serde.decode("toml", fs.readFile("edit-workflow.toml"))
else
	config = {}
end

config.project = config.project or "default.project.json"
config.build_to = config.build_to or "build.rbxl"
config.edit_to = config.edit_to or "edit.rbxl"

return function(workflow)
	if workflow == "build" then
		if fs.metadata(config.build_to).exists then
			print(`Moving existing {config.build_to} to Recycle Bin...`)
			recycle(config.build_to):assert()
			print(`  recycled {config.build_to}`)
		end

		exec({ "rojo", "build", "--output", config.build_to, config.project }):assert()
	elseif workflow == "edit-build" then
		if fs.metadata(config.edit_to).exists then
			print(`Moving existing {config.edit_to} to Recycle Bin...`)
			recycle(config.edit_to):assert()
			print(`  recycled {config.edit_to}`)
		end

		print("Building game...")
		exec({ "rojo", "build", "--output", config.edit_to, config.project }, {
			stdio = {
				stdout = "default",
				stderr = "default",
			},
		}):assert()
		print("  build succeeded")

		print("Opening Roblox Studio. This may take a moment...")
		exec({
			"powershell",
		}, {
			stdin = `([WMICLASS]"win32_process").Create('explorer {config.edit_to}', "{process.cwd}")`,
			stdio = {
				stdout = "none",
				stderr = "none",
			},
		}):assert()
	elseif workflow == "edit" then
		print("Installing wally packages...")
		exec({ "lunar", "wally-install" }, {
			stdio = {
				stdout = "default",
				stderr = "default",
			},
		}):assert()
		print("  wally packages installed")

		local lockFileMeta = fs.metadata(`{config.edit_to}.lock`)
		if lockFileMeta.exists then
			print("Studio lock file exists. Assuming Studio is already open.")
			print(
				`- if {config.edit_to} is {stdio.color("red")}already open, but you want to rebuild it{stdio.color("reset")}, then {stdio.color(
					"blue"
				)}close Roblox Studio first{stdio.color("reset")}.`
			)
			print(
				`- if {config.edit_to} is {stdio.color("red")}not open{stdio.color("reset")}, then {stdio.color("blue")}delete {config.edit_to}.lock{stdio.color(
					"reset"
				)}.`
			)
		else
			if fs.metadata(config.edit_to).exists then
				print(`Moving existing {config.edit_to} to Recycle Bin...`)
				recycle(config.edit_to):assert()
				print(`  recycled {config.edit_to}`)
			end

			print("Building game...")
			exec({ "rojo", "build", "--output", config.edit_to, config.project }, {
				stdio = {
					stdout = "default",
					stderr = "default",
				},
			}):assert()
			print("  build succeeded")

			print("Instaling rojo plugin...")
			exec({ "rojo", "plugin", "install" }, { stdio = { stdout = "default", stderr = "default" } }):assert()
			print("  rojo plugin installed")

			print("Opening Roblox Studio. This may take a moment...")
			exec({
				"powershell",
			}, {
				stdin = `([WMICLASS]"win32_process").Create('explorer config.edit_to', "{process.cwd}")`,
				stdio = {
					stdout = "none",
					stderr = "none",
				},
			}):assert()
		end

		print("Waiting for Studio to open...")
		local timer_start = os.clock()
		while true do
			lockFileMeta = fs.metadata(`{config.edit_to}.lock`)
			if lockFileMeta.exists then
				break
			elseif os.clock() - timer_start > 60 then
				print("Could not find Studio lock file!")
				print("- if Studio is just updating, run this command again when Studio appears.")
				print(
					"- if Studio is not running, it may be stuck. Open task manager and force close it before trying again."
				)
				process.exit(1)
			end

			task.wait(1)
		end
		print("  studio is open")

		print("Starting Rojo server...")
		local rojoProjectPath = `{process.cwd}/default.project.json`

		local response
		local rojoReqSucceeded, _ = pcall(function()
			response = net.request({
				method = "GET",
				url = "http://localhost:34872",
			})
		end)
		if rojoReqSucceeded and response.ok then
			print(`{stdio.color("red")}  Rojo is already running. Please close it first.{stdio.color("reset")}`)
			process.exit(1)
		end

		local exiting = false
		task.spawn(function()
			while not exiting do
				exec({ "rojo", "sourcemap", "-o", "sourcemap.json", "analysis.project.json" }, {
					stdio = {
						stdout = "default",
						stderr = "default",
					},
				})

				local result = exec({ "rojo", "serve", rojoProjectPath }, {
					stdio = {
						stdout = "default",
						stderr = "default",
					},
				})
				if not result.ok and not exiting then
					print(`{stdio.color("yellow")}Rojo server closed unexpectedly. Cause:{stdio.color("reset")}`)
					print(captureRustError(result, "  "))

					print(`{stdio.color("blue")}Restarting rojo server in 5 seconds...{stdio.color("reset")}`)
					task.wait(5)
				end
			end
		end)

		local function exit(code: number)
			exiting = true

			-- Kill Rojo, otherwise it'll keep this Lune runtime open until it's
			-- manually killed by the user (or it otherwise exits)

			local processes = exec(
				{ "wmic", "process", "where", [["name like '%rojo.exe%'"]], "get", "processid,commandline", "/format:list" },
				{
					stdio = {
						stdout = "default",
						stderr = "default",
					},
				}
			):assert()

			for commandline, id in processes.stdout:gmatch("CommandLine=(.-)\r*\nProcessId=(%d+)\r*\n") do
				assert(id)
				if commandline:match("serve (.*)") == rojoProjectPath then
					exec({ "taskkill", "/pid", id, "/f" }, { stdio = { stdout = "default", stderr = "default" } })
				end
			end

			process.exit(code)
		end

		print("  rojo server started")
		print(`{stdio.color("purple")}  Don't forget to connect to the Rojo server in Studio!{stdio.color("reset")}`)

		print("Beginning auto-syncback...")
		print(`{stdio.color("blue")}  Auto-syncback will quit when Studio is closed.{stdio.color("reset")}`)
		print(`{stdio.color("blue")}  Press Ctrl+C at any time to cancel.{stdio.color("reset")}`)

		local fileMeta = fs.metadata(config.edit_to)
		local lastModified = fileMeta.modifiedAt or DateTime.now()
		while true do
			fileMeta = fs.metadata(config.edit_to)
			if fileMeta.modifiedAt and fileMeta.modifiedAt.unixTimestampMillis > lastModified.unixTimestampMillis then
				lastModified = fileMeta.modifiedAt

				print(`{config.edit_to} changed. Syncing back...`)
				local result = exec({ "rojo", "syncback", "-y", "--input", config.edit_to, config.project }, {
					stdio = {
						stdout = "default",
						stderr = "default",
					},
				})
				if not result.ok then
					print(`{stdio.color("yellow")}  syncback failed with status. Cause:{stdio.color("reset")}`)
					print(captureRustError(result, "    "))
				else
					print("  syncback succeeded")
				end
			end

			lockFileMeta = fs.metadata(`{config.edit_to}.lock`)
			if not lockFileMeta.exists then
				print("Studio lock file removed; Studio must be closed. Exiting.")
				exit(0)
			end

			task.wait(1)
		end
	elseif workflow == "edit-syncback" then
		exec({ "rojo", "syncback", "-y", "--input", config.edit_to, config.project }):assert()
	else
		warn("Unknown command:", workflow)
		process.exit(1)
	end
end