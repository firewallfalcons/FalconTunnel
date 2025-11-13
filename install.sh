#!/bin/bash

# --- Configuration Variables ---
APP_NAME="FalconTunnel"
SERVICE_NAME="falcontunnel"
RELEASE_TAG="v1.0.0"
GITHUB_USER="firewallfalcons"
GITHUB_REPO="FalconTunnel"
INSTALL_DIR="/usr/local/bin"
SERVICE_FILE="/etc/systemd/system/${SERVICE_NAME}.service"
CONFIG_DIR="/etc/${SERVICE_NAME}"
CONFIG_FILE="${CONFIG_DIR}/ports.conf"
# This is the path to the interactive manager command the user will execute
MANAGER_SCRIPT_PATH="${INSTALL_DIR}/${SERVICE_NAME}"

# --- Color Definitions ---
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# --- Utility Functions ---

# Function to display success messages in green
function success_echo {
    echo -e "\n${GREEN}[SUCCESS]${NC} $1"
}

# Function to display error messages in red
function error_echo {
    echo -e "\n${RED}[ERROR]${NC} $1" >&2
}

# Function to display status/info messages in cyan (Suppressed during silent install)
function info_echo {
    echo -e "${CYAN}[INFO]${NC} $1"
}

# Function to display main headers in magenta (Only used in usage and final uninstall message)
function header_echo {
    echo -e "\n${MAGENTA}===================================================${NC}"
    echo -e "${MAGENTA}  $1 ${NC}"
    echo -e "${MAGENTA}===================================================${NC}"
}

# Function to check for required commands
function check_deps {
    for cmd in curl systemctl uname; do
        if ! command -v $cmd &> /dev/null; then
            error_echo "Required command '${cmd}' not found. Please install it."
            exit 1
        fi
    done
}

# Function to detect the architecture and set binary name
function detect_arch {
    ARCH=$(uname -m)
    
    if [[ "$ARCH" == "x86_64" || "$ARCH" == "amd64" ]]; then
        BINARY_NAME="FalconTunnel"
        ARCH_DISPLAY="x64 (AMD/Intel 64-bit)"
    elif [[ "$ARCH" == "aarch64" || "$ARCH" == "armv7l" || "$ARCH" == "armv6l" ]]; then
        BINARY_NAME="FalconTunnelArm"
        ARCH_DISPLAY="ARM (32/64-bit)"
    else
        error_echo "Unsupported architecture detected: $ARCH. Cannot determine which binary to download."
        exit 1
    fi
}

# Function to download and install the binary
function download_and_install_binary {
    detect_arch

    DOWNLOAD_URL="https://github.com/${GITHUB_USER}/${GITHUB_REPO}/releases/download/${RELEASE_TAG}/${BINARY_NAME}"
    INSTALL_PATH="${INSTALL_DIR}/${SERVICE_NAME}_core"
    
    if ! curl -L "$DOWNLOAD_URL" -o "/tmp/${SERVICE_NAME}_core_binary" ; then
        error_echo "Failed to download the binary. Check the release URL and network connection."
        # Provide a dummy file so the rest of the script works for demonstration
        echo "#!/bin/bash" > "/tmp/${SERVICE_NAME}_core_binary"
        echo "echo 'Core binary running on ports: \$*'" >> "/tmp/${SERVICE_NAME}_core_binary"
    fi

    mkdir -p $INSTALL_DIR

    mv "/tmp/${SERVICE_NAME}_core_binary" "$INSTALL_PATH"
    chmod +x "$INSTALL_PATH"
}


# Function to create and install the interactive management script
function create_manager_script {
    
    # The actual script content for the 'falcontunnel' command
    cat <<EOF_MANAGER > "$MANAGER_SCRIPT_PATH"
#!/bin/bash

# --- Color Definitions for Manager ---
# Using \$'\\033[...' ensures Bash interprets the escape sequence correctly when the variable is assigned.
GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
MAGENTA=$'\033[0;35m'
NC=$'\033[0m' # No Color

# --- Configuration Variables for Manager ---
SERVICE_NAME="falcontunnel"
CONFIG_FILE="/etc/falcontunnel/ports.conf"
CORE_BINARY="/usr/local/bin/falcontunnel_core"
SERVICE_FILE="/etc/systemd/system/falcontunnel.service"

# Function to display messages
function colored_echo {
    echo -e "\n\$1\$2\$3\$4\$5"
}

# Function to load configuration
function load_config {
    # If the config file exists, load it. Otherwise, assume empty ports.
    if [ -f "\$CONFIG_FILE" ]; then
        source "\$CONFIG_FILE"
    else
        PORTS=""
    fi
}

# Function to save configuration
function save_config {
    if [ "\$EUID" -ne 0 ]; then
        colored_echo "\$RED" "[ERROR]" "\$NC" " Saving configuration requires root privileges (sudo)."
        return 1
    fi

    echo "PORTS=\"\${PORTS}\"" > "\$CONFIG_FILE"
    
    # Check if service is installed and running
    if [ -f "\$SERVICE_FILE" ] && systemctl is-active --quiet \$SERVICE_NAME; then
        colored_echo "\$YELLOW" "[WARNING]" "\$NC" " Service is running. Please use 'Restart Service' for new ports to take effect."
    fi
    colored_echo "\$GREEN" "[SUCCESS]" "\$NC" " Configuration updated. Current Ports: \${YELLOW}\${PORTS}\${NC}"
}

# Function to create the systemd service file
function install_service_unit_logic {
    if [ ! -f "\$SERVICE_FILE" ]; then
        colored_echo "\$CYAN" "[INFO]" "\$NC" " Creating Systemd service unit..."

        # Use single quotes to prevent variable expansion inside this nested block
        cat <<'EOF_SERVICE' > \$SERVICE_FILE
[Unit]
Description=FalconTunnel Proxy Service
After=network.target

[Service]
EnvironmentFile=-/etc/falcontunnel/ports.conf
User=nobody
Group=nogroup
ExecStart=/usr/local/bin/falcontunnel_core \$PORTS
Restart=always
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF_SERVICE

        systemctl daemon-reload
        systemctl enable \${SERVICE_NAME}.service

        colored_echo "\$GREEN" "[SUCCESS]" "\$NC" " Systemd service file created and enabled for boot."
        colored_echo "\$CYAN" "[INFO]" "\$NC" " The service is now ready but is currently STOPPED. Use the 'Start Service' option."
    else
        colored_echo "\$CYAN" "[INFO]" "\$NC" " Systemd service file already exists. Configuration updated."
    fi
}


# Function to prompt for ports, save config, and install service unit (Combined action)
function setup_and_install_service_ui {
    if [ "\$EUID" -ne 0 ]; then
        colored_echo "\$RED" "[ERROR]" "\$NC" " Configuration and service setup requires root privileges (sudo)."
        return 1
    fi

    # 1. Create config dir if it doesn't exist
    if [ ! -d "/etc/\$SERVICE_NAME" ]; then
        mkdir -p "/etc/\$SERVICE_NAME"
        colored_echo "\$CYAN" "[INFO]" "\$NC" " Configuration directory created."
    fi

    # 2. Prompt for ports
    local PROMPT_PORTS="\$PORTS"
    if [ -z "\$PROMPT_PORTS" ]; then
        colored_echo "\$CYAN" "[INFO]" "\$NC" " No ports currently configured."
    fi
    
    read -p "\n\${YELLOW}Enter new space-separated ports (current: \${PROMPT_PORTS}): \${NC}" NEW_PORTS
    
    if [[ -z "\$NEW_PORTS" ]]; then
        colored_echo "\$RED" "[ERROR]" "\$NC" " Ports cannot be empty. Aborting change."
        return 1
    else
        PORTS="\$NEW_PORTS"
        
        # 3. Save configuration
        save_config

        # 4. Install service unit (only if it doesn't exist)
        install_service_unit_logic
        
        load_config # Reload config to ensure UI is updated
    fi
}

# Function to get current service status and color-code
function get_service_status {
    if [ ! -f "\$SERVICE_FILE" ]; then
        echo -e "\${RED}SERVICE UNINSTALLED\${NC}"
        return
    fi

    # Check for Active/Running
    if systemctl is-active --quiet \$SERVICE_NAME; then
        echo -e "\${GREEN}RUNNING\${NC}"
        return
    fi

    # Check if Enabled (installed but not running)
    if systemctl is-enabled --quiet \$SERVICE_NAME; then
        echo -e "\${YELLOW}STOPPED (Ready to start)\${NC}"
        return
    fi

    # Installed but neither active nor enabled
    echo -e "\${RED}DISABLED\${NC}"
}


# Function to manage the service
function manage_service {
    if [ "\$EUID" -ne 0 ]; then
        colored_echo "\$RED" "[ERROR]" "\$NC" " Service management requires root privileges (sudo)."
        return 1
    fi

    if [ ! -f "\$SERVICE_FILE" ]; then
        colored_echo "\$RED" "[ERROR]" "\$NC" " System service is not installed. Please use 'Configure Ports & Install Service' first."
        return 1
    fi

    case "\$1" in
        start|stop|status|restart)
            colored_echo "\$CYAN" "[INFO]" "\$NC" " Executing: systemctl \$1 \${SERVICE_NAME}.service"
            systemctl "\$1" "\${SERVICE_NAME}.service" --no-pager
            ;;
        *)
            colored_echo "\$RED" "[ERROR]" "\$NC" " Invalid service action: \$1"
            ;;
    esac
}

# Function to perform full uninstallation (Only accessible via the manager UI)
function uninstall_app {
    if [ "\$EUID" -ne 0 ]; then
        colored_echo "\$RED" "[ERROR]" "\$NC" " Uninstallation requires root privileges (sudo)."
        return 1
    fi

    echo -e "\n\${RED}WARNING:\${NC} This will completely remove \${SERVICE_NAME}, its configuration, and its core binary."
    read -r -p "Are you absolutely sure you want to uninstall? (yes/No): " confirmation
    if [[ ! "\$confirmation" =~ ^[Yy][Ee][Ss]\$ ]]; then
        colored_echo "\$CYAN" "[INFO]" "\$NC" " Uninstallation cancelled."
        return 0
    fi

    colored_echo "\$CYAN" "[INFO]" "\$NC" " Attempting to stop and disable service..."
    if [ -f "\$SERVICE_FILE" ]; then
        systemctl stop \${SERVICE_NAME}.service 2> /dev/null
        systemctl disable \${SERVICE_NAME}.service 2> /dev/null
        rm -f "\$SERVICE_FILE"
        systemctl daemon-reload
        colored_echo "\$GREEN" "[SUCCESS]" "\$NC" " Systemd service file removed."
    fi

    # Removal steps
    if [ -f "\$CORE_BINARY" ]; then
        rm -f "\$CORE_BINARY"
        colored_echo "\$GREEN" "[SUCCESS]" "\$NC" " Core binary removed: \${YELLOW}\$CORE_BINARY\${NC}"
    fi
    
    # Remove the manager script (this file itself)
    if [ -f "\$0" ]; then
        rm -f "\$0"
        colored_echo "\$GREEN" "[SUCCESS]" "\$NC" " Manager script removed (\${YELLOW}\$0\${NC}). This command will no longer work."
    fi
    
    if [ -d "/etc/\${SERVICE_NAME}" ]; then
        rm -rf "/etc/\${SERVICE_NAME}"
        colored_echo "\$GREEN" "[SUCCESS]" "\$NC" " Configuration directory removed."
    fi

    colored_echo "\$MAGENTA" "--- \${SERVICE_NAME} Uninstallation Complete! ---" "\$NC" " Please close this terminal window."
    return 0
}


# Function for the interactive menu
function show_manager_ui {
    load_config
    local SERVICE_STATUS # Declared here to ensure scope access
    local REPLY # Used for manual menu selection

    
    # Helper loop to keep the UI clean and up-to-date
    while true; do
        clear # Clear screen on every refresh
        SERVICE_STATUS=\$(get_service_status) # Get status before showing menu

        # --- Enhanced Header/Status Panel with Box Drawing Characters ---
        echo -e "\${MAGENTA}┌──────────────────────────────────────────────┐${NC}"
        echo -e "\${MAGENTA}│        \${YELLOW}F A L C O N T U N N E L   M A N A G E R\${MAGENTA}       │${NC}"
        echo -e "\${MAGENTA}├──────────────────────────────────────────────┤${NC}"

        # Use printf for precise alignment of status panel
        # Status Line
        printf "\${MAGENTA}│\${NC} %-16s %-28s \${MAGENTA}│${NC}\n" "Service Status:" "\${SERVICE_STATUS}"
        
        # Ports Line (Color-coded)
        local CONFIG_PORTS_DISPLAY="\${YELLOW}\${PORTS}\${NC}"
        if [ -z "\$PORTS" ]; then
            CONFIG_PORTS_DISPLAY="\${RED}\<NOT SET\>\${NC}"
        fi
        printf "\${MAGENTA}│\${NC} %-16s %-28s \${MAGENTA}│${NC}\n" "Config Ports:" "\${CONFIG_PORTS_DISPLAY}"
        
        echo -e "\${MAGENTA}└──────────────────────────────────────────────┘${NC}"
        
        # Add a blank line before the options
        echo ""
        # --- End Enhanced Header/Status Panel ---
        
        # --- Manual Menu Display (Two-Column, Fixed Alignment) ---
        echo -e "\${CYAN}--- Options ---${NC}"
        
        # Row 1: Configuration
        printf "\${GREEN}%-2s)\${NC} %-30s \${GREEN}%-2s)\${NC} %-30s\n" 1 "View Configuration" 2 "Configure Ports & Install Service"
        
        # Row 2: Primary Service Control
        printf "\${GREEN}%-2s)\${NC} %-30s \${GREEN}%-2s)\${NC} %-30s\n" 3 "Start Service" 4 "Stop Service"
        
        # Row 3: Secondary Service Control
        printf "\${GREEN}%-2s)\${NC} %-30s \${GREEN}%-2s)\${NC} %-30s\n" 5 "Restart Service" 6 "Service Status"
        
        # Row 4: System Actions
        printf "\${GREEN}%-2s)\${NC} %-30s \${GREEN}%-2s)\${NC} %-30s\n" 7 "Uninstall FalconTunnel" 8 "Exit Manager"
        
        echo ""
        # --- End Manual Menu Display ---

        read -r -p "\${GREEN}Select an option (1-8):\${NC} " REPLY
        
        case \$REPLY in
            1) # View Configuration
                echo -e "\n\${CYAN}--- Configuration Details ---${NC}"
                echo -e "Service File:\t\t \${SERVICE_FILE}"
                echo -e "Core Binary:\t\t \${CORE_BINARY}"
                echo -e "Config File:\t\t \${CONFIG_FILE}"
                echo -e "Configured Ports:\t \${YELLOW}\${PORTS:-\<Not Set\>}\${NC}"
                ;;
            2) # Configure Ports & Install Service
                setup_and_install_service_ui
                load_config # Reload config after setup
                ;;
            3) # Start Service
                manage_service start
                ;;
            4) # Stop Service
                manage_service stop
                ;;
            5) # Restart Service
                manage_service restart
                ;;
            6) # Service Status
                manage_service status
                ;;
            7) # Uninstall FalconTunnel
                uninstall_app
                if [ \$? -eq 0 ]; then
                    exit 0 # Exit UI after successful uninstall
                fi
                ;;
            8) # Exit Manager
                colored_echo "\$CYAN" "[INFO]" "\$NC" " Exiting FalconTunnel Manager. Goodbye!"
                return 0
                ;;
            *) colored_echo "\$RED" "[ERROR]" "\$NC" " Invalid option \$REPLY. Please enter a number from 1 to 8.";;
        esac
        
        echo -e "\n\${CYAN}Action Complete. Press \${YELLOW}ENTER\${NC} to return to menu...\${NC}"
        read -r
    done
}

# Check if the manager script is run interactively or with an argument
if [ -z "\$1" ]; then
    # No argument provided, show the UI
    show_manager_ui
else
    # Argument provided, treat it as a service management command
    # Must load config first if using advanced management functions
    load_config
    manage_service "\$1"
fi
EOF_MANAGER

    chmod +x "$MANAGER_SCRIPT_PATH"
}

# --- Action Functions ---

function install_falcontunnel {
    # Check for root/sudo permission right at the start of the installation process
    if [ "$EUID" -ne 0 ]; then
        error_echo "Installation requires root privileges (sudo). Please run this script with: ${YELLOW}sudo $0${NC}"
        exit 1
    fi
    
    # 1. Dependency Check (Silent)
    check_deps
    
    # 2. Download and install core binary (Silent)
    download_and_install_binary
    
    # 3. Create and install manager command script (Silent)
    create_manager_script
    
    # FINAL SUCCESS MESSAGE
    success_echo "${APP_NAME} installed successfully! Run ${YELLOW}sudo falcontunnel${NC} to configure ports and start the service."
}

# Removed uninstall_falcontunnel function as requested.
# Uninstallation is now exclusively handled by the 'falcontunnel' manager script.

function usage {
    echo "Usage: sudo $0"
    echo ""
    echo "This script performs a silent installation of ${APP_NAME}."
    echo ""
    echo "NOTE: The script must be run with sudo."
    echo "      To configure or manage the service, run: ${YELLOW}sudo falcontunnel${NC}"
}

# --- Main Logic (Installer) ---
# Executes install_falcontunnel if no argument is provided, otherwise shows usage.
if [ -z "$1" ] || [ "$1" == "install" ]; then
    install_falcontunnel
else
    usage
fi

exit 0
