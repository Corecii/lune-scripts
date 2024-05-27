# Misc. Lune Scripts

This repository includes a few general-purpose lune scripts I use that I've extracted from my projects.

## Using with Lunar

These scripts can be easily used with [Lunar](https://github.com/corecii/lunar) to run them without copy-and-paste. Just add this file under your `lune`, `lunar`, `.lune`, or `.lunar` folder:

```toml
# corecii-lune-scripts.lunar.toml

[repo]
	url = "https://github.com/corecii/lune-scripts"
```

You can include only specific scripts with the `tasks` field. For example:

```toml
# corecii-lune-scripts.lunar.toml

[repo]
url = "https://github.com/corecii/lune-scripts"
tasks = ["enable-loadmodule", "wally-install"]
```