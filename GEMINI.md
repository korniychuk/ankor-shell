# AnKor Shell Project Overview

## Project Overview

AnKor Shell is a comprehensive library of shell scripts designed to enhance the Bash and Zsh terminal environments. It provides a rich set of utilities for system administration, Git workflow, Node.js version management, and general shell scripting. The project emphasizes extensibility, allowing users to integrate their own custom and local scripts seamlessly. It aims to streamline common development tasks and provide a more powerful and configurable shell experience.

## Main Technologies

*   Bash and Zsh shell scripting
*   Git for version control enhancements
*   Perl for advanced string manipulation and regex operations
*   `n` for Node.js version management

## Architecture

The library is structured with a central `index.sh` file that sources various modules from the `lib` directory and other core scripts.

*   `index.sh`: The primary entry point, responsible for loading all necessary components.
*   `config.sh`: Manages aliases, environment variables, and conditional loading of tools like `gdu` and `nvim`. It also provides a mechanism for project-specific initialization via `.ak-init.sh`.
*   `lib/`: Contains modular shell scripts categorized by functionality (e.g., `git.sh`, `os.sh`, `str.sh`, `shell.sh`).
*   `custom-scripts/` and `local-scripts/`: Directories for user-defined scripts, dynamically loaded by `cals.sh` with `aks.` and `akl.` prefixes, respectively.
*   `.bin/`: A directory where symbolic links to custom/local scripts are created, making them executable as commands.
*   `node-loader.sh`: Implements lazy-loading for Node.js using the `n` version manager, automatically detecting project-specific Node.js versions.
*   `disk-aliases.sh`: Provides quick navigation aliases for common directory paths.

## Building and Running

AnKor Shell is not a traditional "built" project in the sense of compilation. It's a collection of scripts that are "sourced" into the user's shell environment.

1.  **Clone the repository:**
    ```bash
    git clone git@github.com:korniychuk/ankor-shell.git
    cd ankor-shell
    ```

2.  **Load the library into your shell:**
    Add the following lines to your `~/.bashrc` or `~/.zshrc` file:
    ```bash
    # AnKor Shell Library
    source "/path/to/ankor-shell/index.sh"
    source "${AK_SCRIPT_PATH}/disk-aliases.sh" "/Volumes" # Adjust "/Volumes" as needed
    source "${AK_SCRIPT_PATH}/node-loader.sh"
    source "${AK_SCRIPT_PATH}/cals.sh"
    ```
    (Replace `/path/to/ankor-shell/` with the actual path where you cloned the repository).

3.  **Reload your shell configuration:**
    ```bash
    source ~/.bashrc # or ~/.zshrc
    ```

## Testing

The project does not explicitly define a testing framework or commands in the analyzed files. However, individual functions and scripts are expected to be tested through their usage and manual verification.

## Development Conventions

*   **Prefixing:** Functions and variables are consistently prefixed with `ak.` (e.g., `ak.sh.type`, `ak.git.getCurrentBranch`). Custom and local scripts are prefixed with `aks.` and `akl.` respectively.
*   **Documentation:** Functions include comments detailing their purpose, parameters, examples, and helpful links.
*   **TODOs:** The codebase contains numerous `TODO` comments, indicating ongoing development, planned features, and areas for improvement.
*   **Shell Compatibility:** Efforts are made to ensure compatibility between Bash and Zsh, with conditional logic for OS-specific features (e.g., macOS).
*   **Error Handling:** Functions often include basic argument validation and error messaging (e.g., `ak.sh.die`, `ak.sh.param.required`).
*   **Colors:** Utilizes ANSI escape codes for colored terminal output to improve readability of messages.
*   **Perl Dependency:** Some advanced string and Git manipulations rely on Perl for regular expression capabilities.
