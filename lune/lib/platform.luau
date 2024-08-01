local process = require("@lune/process")

export type platform = "windows" | "macos" | "linux"

if process.env.OS == "Windows_NT" then
	return "windows"
else
	return "linux"
end

-- TODO: impl mac
