#!/usr/bin/env bash
# ==============================================================================
# Pokefetch Installer
# ==============================================================================
# Automates:
#  1. Prompting user for fetch backend preference (fastfetch or neofetch)
#  2. Checking and installing required packages (jp2a, fastfetch/neofetch, shuf)
#  3. Backing up and updating ~/.bash_functions with the pokefetch function
#  4. Ensuring ~/.bash_functions is sourced in ~/.bashrc
#  5. Cleaning previous startup output and adding the run line to ~/.bashrc
# ==============================================================================

set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_SPRITES_DIR="${SCRIPT_DIR}/neofetch"
SPRITES_DIR="${DEFAULT_SPRITES_DIR}"
SHINY_THRESHOLD=95
BACKEND=""
NON_INTERACTIVE=false
FORCE=false
ACTION="install"

BASHRC_FILE="${HOME}/.bashrc"
BASH_FUNCTIONS_FILE="${HOME}/.bash_functions"
BASH_FUNCTIONS_BACKUP="${HOME}/.bash_functions_bu"

# Colors for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

error() {
    echo -e "${RED}[ERROR]${NC} $*" >&2
}

print_header() {
    echo -e "${CYAN}${BOLD}"
    echo "============================================================"
    echo "                 POKEFETCH INSTALLER                        "
    echo "============================================================"
    echo -e "${NC}"
}

show_help() {
    echo "Usage: ./install.sh [OPTIONS]"
    echo
    echo "Options:"
    echo "  -b, --backend <name>     Fetch backend to use: 'fastfetch' or 'neofetch'"
    echo "  -f, --fastfetch          Use fastfetch backend (faster, modern)"
    echo "  -n, --neofetch           Use neofetch backend (classic)"
    echo "  -p, --path <path>        Custom path to neofetch/ sprites directory"
    echo "  -t, --threshold <0-100>  Normal pokemon threshold percentage (default: 95)"
    echo "  --force                  Reinstall/overwrite if Pokefetch is already installed"
    echo "  -y, --yes                Non-interactive mode; accept defaults"
    echo "  -u, --uninstall          Remove pokefetch from ~/.bashrc and ~/.bash_functions"
    echo "  -h, --help               Display this help message"
    echo
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        -b|--backend)
            BACKEND="$2"
            shift 2
            ;;
        -f|--fastfetch)
            BACKEND="fastfetch"
            shift
            ;;
        -n|--neofetch)
            BACKEND="neofetch"
            shift
            ;;
        -p|--path)
            SPRITES_DIR="$2"
            shift 2
            ;;
        -t|--threshold)
            SHINY_THRESHOLD="$2"
            shift 2
            ;;
        --force|--reinstall)
            FORCE=true
            shift
            ;;
        -y|--yes|--non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        -u|--uninstall)
            ACTION="uninstall"
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

detect_package_manager() {
    if command -v apt-get >/dev/null 2>&1; then
        echo "apt"
    elif command -v pacman >/dev/null 2>&1; then
        echo "pacman"
    elif command -v dnf >/dev/null 2>&1; then
        echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then
        echo "zypper"
    elif command -v brew >/dev/null 2>&1; then
        echo "brew"
    else
        echo "unknown"
    fi
}

install_package() {
    local pkg_manager="$1"
    local package="$2"

    info "Attempting to install '${package}' using ${pkg_manager}..."
    case "$pkg_manager" in
        apt)
            sudo apt-get update && sudo apt-get install -y "$package"
            ;;
        pacman)
            sudo pacman -S --needed --noconfirm "$package"
            ;;
        dnf)
            sudo dnf install -y "$package"
            ;;
        zypper)
            sudo zypper install -y "$package"
            ;;
        brew)
            brew install "$package"
            ;;
        *)
            error "No supported package manager found to install '${package}'. Please install it manually."
            return 1
            ;;
    esac
}

install_fastfetch_apt() {
    info "Checking fastfetch availability in apt..."
    if apt-cache show fastfetch >/dev/null 2>&1; then
        sudo apt-get update && sudo apt-get install -y fastfetch
    else
        info "fastfetch not available in default apt repositories."
        if command -v add-apt-repository >/dev/null 2>&1; then
            info "Adding PPA ppa:zhangsongcui3371/fastfetch..."
            sudo add-apt-repository -y ppa:zhangsongcui3371/fastfetch
            sudo apt-get update
            sudo apt-get install -y fastfetch
        else
            info "add-apt-repository not found. Attempting to download official .deb package from GitHub..."
            local arch
            arch="$(dpkg --print-architecture 2>/dev/null || echo "amd64")"
            local deb_url="https://github.com/fastfetch-cli/fastfetch/releases/latest/download/fastfetch-linux-${arch}.deb"
            local tmp_deb="/tmp/fastfetch.deb"
            if command -v curl >/dev/null 2>&1; then
                curl -fsSL -o "$tmp_deb" "$deb_url"
            elif command -v wget >/dev/null 2>&1; then
                wget -qO "$tmp_deb" "$deb_url"
            else
                error "Neither curl nor wget is available to download fastfetch deb."
                return 1
            fi
            sudo dpkg -i "$tmp_deb" || sudo apt-get install -f -y
            rm -f "$tmp_deb"
        fi
    fi
}

check_and_install_dependencies() {
    local target_backend="$1"
    local pm
    pm="$(detect_package_manager)"

    info "Verifying required tools for Pokefetch..."

    # Check shuf (coreutils)
    if ! command -v shuf >/dev/null 2>&1; then
        warn "'shuf' command not found. Installing coreutils..."
        install_package "$pm" "coreutils" || true
    fi

    # Check jp2a
    if command -v jp2a >/dev/null 2>&1; then
        success "Found jp2a: $(command -v jp2a)"
    else
        warn "'jp2a' is not installed. Installing jp2a..."
        install_package "$pm" "jp2a"
        if ! command -v jp2a >/dev/null 2>&1; then
            error "Failed to install 'jp2a'. Please install jp2a manually."
            exit 1
        fi
        success "jp2a installed successfully."
    fi

    # Check chosen backend
    if [[ "$target_backend" == "fastfetch" ]]; then
        if command -v fastfetch >/dev/null 2>&1; then
            success "Found fastfetch: $(command -v fastfetch)"
        else
            warn "'fastfetch' is not installed. Installing fastfetch..."
            if [[ "$pm" == "apt" ]]; then
                install_fastfetch_apt
            else
                install_package "$pm" "fastfetch"
            fi
            if ! command -v fastfetch >/dev/null 2>&1; then
                error "Failed to install 'fastfetch'. Please install it manually or select neofetch."
                exit 1
            fi
            success "fastfetch installed successfully."
        fi
    elif [[ "$target_backend" == "neofetch" ]]; then
        if command -v neofetch >/dev/null 2>&1; then
            success "Found neofetch: $(command -v neofetch)"
        else
            warn "'neofetch' is not installed. Installing neofetch..."
            install_package "$pm" "neofetch"
            if ! command -v neofetch >/dev/null 2>&1; then
                error "Failed to install 'neofetch'. Please install it manually."
                exit 1
            fi
            success "neofetch installed successfully."
        fi
    fi
}

uninstall_pokefetch() {
    print_header
    info "Starting Pokefetch uninstallation..."

    # 1. Clean ~/.bash_functions
    if [[ -f "$BASH_FUNCTIONS_FILE" ]]; then
        cp "$BASH_FUNCTIONS_FILE" "$BASH_FUNCTIONS_BACKUP"
        info "Created backup: ${BASH_FUNCTIONS_BACKUP}"
        python3 -c "
import re
with open('${BASH_FUNCTIONS_FILE}', 'r') as f:
    content = f.read()
cleaned = re.sub(r'(?m)^#\s*Pokefetch.*?\n(?:pokefetch\(\)\s*\{[\s\S]*?^\}\n?|pokefetch\(\)\s*\{[\s\S]*?\n\})\n?', '', content)
cleaned = re.sub(r'(?m)^pokefetch\(\)\s*\{[\s\S]*?^\}\n?', '', cleaned)
with open('${BASH_FUNCTIONS_FILE}', 'w') as f:
    f.write(cleaned)
" 2>/dev/null || true
        success "Removed pokefetch function from ${BASH_FUNCTIONS_FILE}"
    fi

    # 2. Clean ~/.bashrc
    if [[ -f "$BASHRC_FILE" ]]; then
        python3 -c "
import re
with open('${BASHRC_FILE}', 'r') as f:
    content = f.read()
pattern = r'(?m)(?:^[ \t]*#.*?(?:[Pp]okefetch|Path/to/neofetch).*?\n)*^[ \t]*clear[ \t]*\n^[ \t]*pokefetch.*?\n?'
cleaned = re.sub(pattern, '', content)
# Also catch standalone pokefetch calls
cleaned = re.sub(r'(?m)^[ \t]*pokefetch.*?\n', '', cleaned)
with open('${BASHRC_FILE}', 'w') as f:
    f.write(cleaned)
" 2>/dev/null || true
        success "Removed pokefetch run lines from ${BASHRC_FILE}"
    fi

    success "Pokefetch has been uninstalled."
    info "You can revert ~/.bash_functions from ~/.bash_functions_bu if needed."
}

check_already_installed() {
    local detected=false

    # Check ~/.bash_functions for pokefetch function
    if [[ -f "$BASH_FUNCTIONS_FILE" ]] && grep -qE "(^|\s)pokefetch\(\)" "$BASH_FUNCTIONS_FILE" 2>/dev/null; then
        detected=true
    fi

    # Check ~/.bashrc for pokefetch call
    if [[ -f "$BASHRC_FILE" ]] && grep -qE "(^|\s)pokefetch(\s|$)" "$BASHRC_FILE" 2>/dev/null; then
        detected=true
    fi

    if [[ "$detected" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Main installation routine
do_install() {
    print_header

    # Step 0: Check if Pokefetch is already installed
    if check_already_installed; then
        warn "Pokefetch is already detected in your environment (~/.bashrc or ~/.bash_functions)."
        if [[ "$FORCE" == true ]]; then
            info "'--force' flag specified. Proceeding with clean update/reinstall..."
        elif [[ "$NON_INTERACTIVE" == true || ! -t 0 ]]; then
            info "Skipping install to prevent duplicate entries (run with --force to overwrite)."
            exit 0
        else
            echo
            echo "Options:"
            echo "  1) Reinstall / Update existing configuration"
            echo "  2) Skip install and exit"
            echo
            read -r -p "Enter choice [1/2, default: 2]: " skip_choice
            case "$skip_choice" in
                1|"reinstall"|"update"|"yes"|"y")
                    info "Proceeding with clean update/reinstall..."
                    ;;
                *)
                    info "Skipping install. Your existing Pokefetch configuration remains unchanged."
                    exit 0
                    ;;
            esac
        fi
    fi

    # Step 1: Prompt for fetch tool preference if not provided
    if [[ -z "$BACKEND" ]]; then
        if [[ "$NON_INTERACTIVE" == true || ! -t 0 ]]; then
            BACKEND="fastfetch"
            info "Non-interactive mode: defaulting to fastfetch backend."
        else
            echo "Which fetch tool would you like to use for Pokefetch?"
            echo "  1) fastfetch (Recommended - modern and significantly faster)"
            echo "  2) neofetch  (Classic fetch tool)"
            echo
            read -r -p "Enter choice [1/2, default: 1]: " user_choice
            case "$user_choice" in
                2|"neofetch"|"neo")
                    BACKEND="neofetch"
                    ;;
                *)
                    BACKEND="fastfetch"
                    ;;
            esac
        fi
    fi

    # Normalize backend string
    BACKEND="$(echo "$BACKEND" | tr '[:upper:]' '[:lower:]')"
    if [[ "$BACKEND" != "fastfetch" && "$BACKEND" != "neofetch" ]]; then
        error "Invalid backend '${BACKEND}'. Please choose 'fastfetch' or 'neofetch'."
        exit 1
    fi
    info "Selected backend: ${BOLD}${BACKEND}${NC}"

    # Step 2: Validate sprites directory
    # Resolve absolute path
    SPRITES_DIR="$(cd "$SPRITES_DIR" 2>/dev/null && pwd || echo "$SPRITES_DIR")"
    if [[ ! -d "${SPRITES_DIR}/Pokemon" || ! -d "${SPRITES_DIR}/shiny" ]]; then
        error "Sprites directory invalid: '${SPRITES_DIR}'"
        error "Must contain 'Pokemon' and 'shiny' subdirectories."
        exit 1
    fi
    success "Found valid sprites directory at: ${SPRITES_DIR}"

    # Step 3: Check & install dependencies
    check_and_install_dependencies "$BACKEND"

    # Step 4: Setup ~/.bash_functions
    info "Configuring ~/.bash_functions..."
    if [[ -f "$BASH_FUNCTIONS_FILE" ]]; then
        cp "$BASH_FUNCTIONS_FILE" "$BASH_FUNCTIONS_BACKUP"
        success "Backed up existing ~/.bash_functions to ~/.bash_functions_bu"

        # Remove any existing pokefetch function definition before appending
        python3 -c "
import re
with open('${BASH_FUNCTIONS_FILE}', 'r') as f:
    content = f.read()
cleaned = re.sub(r'(?m)^#\s*(?:New function setup using org|Pokefetch function).*?\n(?:pokefetch\(\)\s*\{[\s\S]*?^\}\n?|pokefetch\(\)\s*\{[\s\S]*?\n\})\n?', '', content)
cleaned = re.sub(r'(?m)^pokefetch\(\)\s*\{[\s\S]*?^\}\n?', '', cleaned)
with open('${BASH_FUNCTIONS_FILE}', 'w') as f:
    f.write(cleaned)
" 2>/dev/null || true
    else
        touch "$BASH_FUNCTIONS_FILE"
        echo "# ~/.bash_functions - User-defined functions" >> "$BASH_FUNCTIONS_FILE"
        info "Created new ~/.bash_functions file."
    fi

    # Prepare portable path with ~ if under $HOME
    local display_sprites_path="${SPRITES_DIR}"
    if [[ "$SPRITES_DIR" == "$HOME"* ]]; then
        display_sprites_path="~${SPRITES_DIR#$HOME}"
    fi

    # Append appropriate function based on backend
    if [[ "$BACKEND" == "fastfetch" ]]; then
        cat << EOF >> "$BASH_FUNCTIONS_FILE"

# Pokefetch function using fastfetch
pokefetch() {
    local pokefetch_path="\${1:-${display_sprites_path}}"
    local shiny_threshold="\${2:-${SHINY_THRESHOLD}}"

    if [ ! -d "\$pokefetch_path/Pokemon" ] || [ ! -d "\$pokefetch_path/shiny" ]; then
        echo "Pokefetch error: Directory '\$pokefetch_path' does not contain Pokemon/ or shiny/ folders." >&2
        return 1
    fi

    local normal shiny poke ascii_art
    normal=\$(ls "\$pokefetch_path/Pokemon" | shuf -n 1)
    shiny=\$(ls "\$pokefetch_path/shiny" | shuf -n 1)

    if [ \$(( RANDOM % 101 )) -gt "\$shiny_threshold" ]; then
        poke="\$pokefetch_path/shiny/\$shiny"
    else
        poke="\$pokefetch_path/Pokemon/\$normal"
    fi

    # Convert image to ASCII using jp2a and display via fastfetch
    ascii_art=\$(jp2a --colors --width=60 "\$poke")
    fastfetch --data "\$ascii_art" --logo-type data
}
EOF
    else
        cat << EOF >> "$BASH_FUNCTIONS_FILE"

# Pokefetch function using neofetch
pokefetch() {
    local pokefetch_path="\${1:-${display_sprites_path}}"
    local shiny_threshold="\${2:-${SHINY_THRESHOLD}}"

    if [ ! -d "\$pokefetch_path/Pokemon" ] || [ ! -d "\$pokefetch_path/shiny" ]; then
        echo "Pokefetch error: Directory '\$pokefetch_path' does not contain Pokemon/ or shiny/ folders." >&2
        return 1
    fi

    local normal shiny poke
    normal=\$(ls "\$pokefetch_path/Pokemon" | shuf -n 1)
    shiny=\$(ls "\$pokefetch_path/shiny" | shuf -n 1)

    if [ \$(( RANDOM % 101 )) -gt "\$shiny_threshold" ]; then
        poke="\$pokefetch_path/shiny/\$shiny"
    else
        poke="\$pokefetch_path/Pokemon/\$normal"
    fi

    neofetch --jp2a "\$poke" --colors 10 12 0 12 15
    echo "\$normal" "\$shiny"
}
EOF
    fi
    success "Appended pokefetch function to ~/.bash_functions"

    # Step 5: Configure ~/.bashrc
    info "Configuring ~/.bashrc..."
    if [[ ! -f "$BASHRC_FILE" ]]; then
        touch "$BASHRC_FILE"
    fi

    # Ensure ~/.bashrc sources ~/.bash_functions
    if ! grep -q "bash_functions" "$BASHRC_FILE" 2>/dev/null; then
        cat << 'EOF' >> "$BASHRC_FILE"

# Source ~/.bash_functions if present
if [ -f ~/.bash_functions ]; then
    . ~/.bash_functions
fi
EOF
        info "Added sourcing of ~/.bash_functions to ~/.bashrc"
    fi

    # Clean previous pokefetch run lines across ~/.bashrc
    python3 -c "
import re
with open('${BASHRC_FILE}', 'r') as f:
    content = f.read()

# Remove any old clear + pokefetch blocks and related comments
pattern = r'(?m)(?:^[ \t]*#.*?(?:[Pp]okefetch|Path/to/neofetch).*?\n)*^[ \t]*clear[ \t]*\n^[ \t]*pokefetch.*?\n?'
cleaned = re.sub(pattern, '', content)

# Remove standalone pokefetch lines if any remain
cleaned = re.sub(r'(?m)^[ \t]*pokefetch.*?\n', '', cleaned)

# Clean up trailing blank lines
cleaned = cleaned.rstrip() + '\n'

with open('${BASHRC_FILE}', 'w') as f:
    f.write(cleaned)
" 2>/dev/null || true

    # Append run line to the end of ~/.bashrc after clearing any previous output
    cat << EOF >> "$BASHRC_FILE"

# Remember to change ~/Path/to/neofetch below to make this work as expected
clear
pokefetch ${display_sprites_path} ${SHINY_THRESHOLD}
EOF

    success "Added pokefetch run line to the end of ~/.bashrc"

    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}             POKEFETCH INSTALLATION COMPLETE!               ${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo
    echo -e "  ${BOLD}Backend:${NC}         ${BACKEND}"
    echo -e "  ${BOLD}Sprites Path:${NC}    ${display_sprites_path}"
    echo -e "  ${BOLD}Normal Chance:${NC}   ${SHINY_THRESHOLD}% (${BOLD}$(( 100 - SHINY_THRESHOLD ))% shiny${NC})"
    echo -e "  ${BOLD}Functions File:${NC}  ${BASH_FUNCTIONS_FILE}"
    echo -e "  ${BOLD}Startup Config:${NC}  ${BASHRC_FILE}"
    echo
    echo -e "${CYAN}To activate now in your current session, run:${NC}"
    echo -e "  ${BOLD}source ~/.bashrc${NC}"
    echo
    echo -e "${CYAN}Or simply open a new terminal window to see your Pokemon!${NC}"
    echo
}

if [[ "$ACTION" == "uninstall" ]]; then
    uninstall_pokefetch
else
    do_install
fi
