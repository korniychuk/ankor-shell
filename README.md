# AnKor Shell

### Usage

#### 1. Clone repository to somewhere

```bash
cd /code # just for example
git clone git@github.com:korniychuk/ankor-shell.git
```

#### 2. Load the library

Add next lines of code to your `~/.bashrc` / `~/.zshrc` configs
```bash
# AnKor Shell Library
source "/code/ankor-shell/index.sh"
source "${AK_SCRIPT_PATH}/disk-aliases.sh" "/Volumes"
source "${AK_SCRIPT_PATH}/node-loader.sh"
source "${AK_SCRIPT_PATH}/cals.sh"
```

#### 3. Custom Scripts repository

```bash
rm custom-scripts/.gitkeep
git clone git@github.com:korniychuk/ankor-shell_custom-scripts.git custom-scripts
```

#### Helpful links

* ASCII - https://patorjk.com/software/taag/#p=display&h=1&f=3D-ASCII&t=ankor-shell
* https://github.com/bashup
* https://github.com/vlisivka/bash-modules - an interesting bash project that implements:
  - modules
  - log functions with colorized output
  - panic fn
  - strict mode
  - error handling
