English | [日本語(Japanese)](https://github.com/signothecat/zsnake/blob/develop/README.ja.md)

<img width="400" alt="zsnake" src="https://github.com/user-attachments/assets/c50d7d2b-ae32-45fe-8dc4-9d7e4f84d186" />

# zsnake

**A retro snake game for your terminal** :snake:

<img src="https://github.com/user-attachments/assets/274ec216-55f1-4e37-9ec0-eaf1074db9ad" width="50%">

## Table of Contents

- [Features](#features)
- [Requirements](#requirements)
- [Installation](#installation)
  - [Local Run (Simple)](#local-run-simple)
  - [Global Install (Play Anywhere)](#global-install-play-anywhere)
- [FAQ](#faq)
  - [How can I uninstall zsnake?](#how-can-i-uninstall-zsnake)
- [Contributing](#contributing)
- [License](#license)

## Features

- Simple / Retro / Classic snake game
- Play with ⬅️⬆️⬇️➡️ **arrow keys**, **W/A/S/D**, or **h/j/k/l**

## Requirements

- Zsh 5.8+

Notes: The game is rendered using Unicode characters.\
On ASCII-only terminals, the display may be misaligned or garbled.\
(This issue is WIP)

## Installation

### Local Run (Simple)

Clone the repository:

```zsh
git clone https://github.com/signothecat/zsnake.git
```

Move to the directory:

```zsh
cd zsnake
```

Run the game:

```zsh
zsh zsnake.zsh
```

### Global Install (Play Anywhere)

Clone the repository:

```zsh
git clone https://github.com/signothecat/zsnake.git
```

Move to the directory:

```zsh
cd zsnake
```

Copy `zsnake.zsh` as `/usr/local/bin/zsnake`:

```zsh
sudo cp zsnake.zsh /usr/local/bin/zsnake
```

Run the game:

```zsh
zsnake
```

## FAQ

### How can I uninstall zsnake?

If you cloned the repository locally, simply delete the `zsnake` folder.

```zsh
rm -rf zsnake
```

If you installed it globally by copying to `/usr/local/bin`, remove `/usr/local/bin/zsnake`.

```zsh
sudo rm /usr/local/bin/zsnake
```

## Contributing

This project is still a work in progress.\
Issues or pull requests are very welcome! 🙏\
X(Twitter): [@signothecat](https://x.com/signothecat)

## License

MIT License © 2025 signothecat
