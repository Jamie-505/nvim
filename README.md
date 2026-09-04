# Neovim Config

## Needed Packages
- fd
- fzf
- node/npm
- ripgrep

## Optional Packages
- cargo (for installing json5 parser to load vscode launch.json)
- go (for installing hyprls)
- yazi

## NPM Packages
- nodemon

## Fonts
Install the fonts from the `fonts/` directory to get nice symbols for vim-flog

## MacOS
### VSCODE launch.json parsing (optional)
If you want to use vscode launch.json parsing and you are using a Apple Silicon Mac, configure cargo as shown down below (cargo needs to be installed of course):
Put this into `~/.cargo/config`:
```toml
[target.x86_64-apple-darwin]
rustflags = [
    "-C", "link-arg=-undefined",
    "-C", "link-arg=dynamic_lookup",
]

[target.aarch64-apple-darwin]
rustflags = [
    "-C", "link-arg=-undefined",
    "-C", "link-arg=dynamic_lookup",
]
```
