#!/usr/bin/env bash
# Claude Runner Installer - Enhanced with FZF directory picker
# Self-contained installer for Claude Runner - runs Claude Code in Docker

set -euo pipefail

# Function to expand tilde to home directory
expand_tilde() {
    local path="$1"
    if [[ "$path" == "~" ]]; then
        echo "$HOME"
    elif [[ "$path" == "~/"* ]]; then
        echo "$HOME/${path#~/}"
    else
        echo "$path"
    fi
}

# Function to validate directory path and name
validate_directory_path() {
    local path="$1"
    
    # Check for empty path
    if [[ -z "$path" ]]; then
        echo "❌ Error: Empty directory path" >&2
        return 1
    fi
    
    # Check for paths containing newlines or carriage returns
    if [[ "$path" == *$'\n'* ]] || [[ "$path" == *$'\r'* ]]; then
        echo "❌ Error: Directory path contains newline characters: $path" >&2
        return 1
    fi
    
    # Check for paths containing control characters or emojis
    if [[ "$path" =~ [[:cntrl:]] ]] || [[ "$path" =~ [🔍📁❌✅🎯💡🚀📖📥📁] ]]; then
        echo "❌ Error: Directory path contains invalid characters (emojis/control chars): $path" >&2
        return 1
    fi
    
    # Check for excessively long paths
    if [[ ${#path} -gt 255 ]]; then
        echo "❌ Error: Directory path too long (${#path} chars): ${path:0:50}..." >&2
        return 1
    fi
    
    # Check for paths that look like output text
    if [[ "$path" == *"Finding"* ]] || [[ "$path" == *"Select"* ]] || [[ "$path" == *"directory"* ]]; then
        echo "❌ Error: Directory path appears to be output text rather than a valid path: $path" >&2
        return 1
    fi
    
    return 0
}

# Function to find project directories with enhanced scoring
find_project_directories() {
    local search_dirs=("$HOME" "$HOME/code" "$HOME/projects" "$HOME/dev" "$HOME/src" "$HOME/workspace")
    local temp_file=$(mktemp)
    
    # Add the expanded home directory to results for easy access
    echo "$HOME" > "$temp_file"
    
    # Find directories with project markers
    for dir in "${search_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            # Look for directories containing project markers
            find "$dir" -maxdepth 3 -type f \( \
                -name package.json -o \
                -name requirements.txt -o \
                -name go.mod -o \
                -name Cargo.toml -o \
                -name pom.xml -o \
                -name build.gradle \
            \) -exec dirname {} \; 2>/dev/null
            
            # Also find .git directories (they're directories, not files)
            find "$dir" -maxdepth 3 -type d -name .git -exec dirname {} \; 2>/dev/null
            
            # Find directories in common project locations
            find "$dir" -maxdepth 2 -type d 2>/dev/null | grep -E "(src|projects|code|apps|services)" | head -20
        fi
    done >> "$temp_file"
    
    # Remove duplicates, normalize paths, and sort with priority scoring
    cat "$temp_file" | sort -u | while read -r path; do
        # Skip if path doesn't exist or is not readable
        [[ -d "$path" && -r "$path" ]] || continue
        
        # Get just the directory name for scoring
        local dir_name=$(basename "$path")
        local parent_name=$(basename "$(dirname "$path")")
        
        # Score based on directory characteristics
        local score=50  # Base score
        
        # Boost score for shorter paths (likely more relevant)
        local depth=$(echo "$path" | tr '/' '\n' | wc -l)
        score=$((score + (10 - depth) * 2))
        
        # Boost score if directory name suggests it's a project
        case "$dir_name" in
            *project*|*code*|*dev*|*src*|*app*|*service*|*api*|*web*|*cli*|*tool*)
                score=$((score + 20))
                ;;
        esac
        
        # Boost if it's in a common code directory
        case "$parent_name" in
            code|projects|dev|src|workspace)
                score=$((score + 15))
                ;;
        esac
        
        # Boost if it contains actual project files
        if [[ -f "$path/.git/config" ]]; then
            score=$((score + 30))
        fi
        if [[ -f "$path/package.json" ]] || [[ -f "$path/requirements.txt" ]] || [[ -f "$path/go.mod" ]] || [[ -f "$path/Cargo.toml" ]]; then
            score=$((score + 25))
        fi
        
        # Output with score for sorting
        printf "%03d:%s\n" "$score" "$path"
    done | sort -rn | cut -d: -f2
    
    rm -f "$temp_file"
}

# Function to create enhanced preview command with directory info
create_preview_command() {
    cat << 'EOF'
bash -c '
dir="$1"
if [[ ! -d "$dir" ]]; then
    echo "❌ Directory not found: $dir"
    exit 0
fi

# Header with directory name and path
echo "📁 $(basename "$dir")"
echo "🔗 $dir"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Git status if available
if [[ -d "$dir/.git" ]]; then
    echo "🔄 Git Repository"
    cd "$dir" 2>/dev/null && {
        branch=$(git branch --show-current 2>/dev/null || echo "unknown")
        status=$(git status --porcelain 2>/dev/null | wc -l | tr -d " ")
        echo "   Branch: $branch"
        echo "   Changes: $status files"
    }
    echo ""
fi

# Project type detection
project_type=""
if [[ -f "$dir/package.json" ]]; then
    project_type="Node.js"
    if [[ -f "$dir/package-lock.json" ]]; then project_type="$project_type (npm)"; fi
    if [[ -f "$dir/yarn.lock" ]]; then project_type="$project_type (yarn)"; fi
elif [[ -f "$dir/requirements.txt" ]] || [[ -f "$dir/pyproject.toml" ]]; then
    project_type="Python"
elif [[ -f "$dir/go.mod" ]]; then
    project_type="Go"
elif [[ -f "$dir/Cargo.toml" ]]; then
    project_type="Rust"
elif [[ -f "$dir/pom.xml" ]]; then
    project_type="Java (Maven)"
elif [[ -f "$dir/build.gradle" ]]; then
    project_type="Java/Kotlin (Gradle)"
elif [[ -f "$dir/Makefile" ]]; then
    project_type="C/C++ (Make)"
fi

if [[ -n "$project_type" ]]; then
    echo "🛠️  Project Type: $project_type"
    echo ""
fi

# Directory size and file count
if command -v du &>/dev/null; then
    size=$(du -sh "$dir" 2>/dev/null | cut -f1 || echo "unknown")
    echo "💾 Size: $size"
fi

file_count=$(find "$dir" -maxdepth 1 -type f 2>/dev/null | wc -l | tr -d " ")
dir_count=$(find "$dir" -maxdepth 1 -type d 2>/dev/null | wc -l | tr -d " ")
echo "📊 Contents: $file_count files, $((dir_count - 1)) subdirs"
echo ""

# Show directory contents (limited)
echo "📋 Directory Contents:"
ls_output=$(ls -la "$dir" 2>/dev/null | head -8)
if [[ -n "$ls_output" ]]; then
    echo "$ls_output"
else
    echo "   (Cannot access directory contents)"
fi

# Show more files if directory has many items
total_items=$(ls -1 "$dir" 2>/dev/null | wc -l | tr -d " ")
if [[ $total_items -gt 7 ]]; then
    echo "   ... and $((total_items - 7)) more items"
fi
' _ {}
EOF
}

# Function to show FZF help overlay
show_fzf_help() {
    cat << 'EOF'
🎯 Claude Runner Directory Picker - Keyboard Shortcuts
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Navigation:
  ↑/↓ or j/k    Navigate up/down
  Page Up/Down  Jump by page
  Home/End      Go to first/last item
  Tab           Multi-select toggle
  
Search & Filter:
  Type          Fuzzy search directories
  Ctrl+R        Toggle search mode
  Alt+C         Toggle case sensitivity
  
Preview & Info:
  Ctrl+/        Toggle preview window
  Ctrl+U        Preview scroll up
  Ctrl+D        Preview scroll down
  
Actions:
  Enter         Select directory
  Ctrl+M        Create new directory at selection
  Ctrl+O        Open directory in file manager
  Esc/Ctrl+C    Cancel selection
  
Help:
  Ctrl+H        Show/hide this help
  ?             Show/hide this help

Tips:
• Type partial directory names for fuzzy matching
• Preview shows project type, git status, and contents
• Use ~ for home directory or type full paths
• Ctrl+M creates missing directories on-the-fly

Press any key to continue...
EOF
}

# Function to pick directory with fzf
pick_directory_with_fzf() {
    echo "🔍 Finding project directories..." >&2
    local projects=$(find_project_directories)
    [[ -z "$projects" ]] && { echo "❌ No project directories found. Usage: $0 /path/to/directory" >&2; exit 1; }
    
    echo "📁 Opening enhanced directory picker..." >&2
    echo "💡 Tip: Press Ctrl+H for help, Ctrl+/ to toggle preview" >&2
    
    # Create preview command
    local preview_cmd=$(create_preview_command)
    
    # Enhanced fzf configuration with advanced features
    local selected=$(echo "$projects" | fzf \
        --height 20 \
        --min-height 15 \
        --reverse \
        --border rounded \
        --margin 1 \
        --padding 1 \
        --prompt "📂 Install Claude Runner in: " \
        --header "Type to search • Ctrl+H for help • Ctrl+/ toggle preview • Tab multi-select" \
        --header-lines 0 \
        --info inline \
        --multi \
        --preview "$preview_cmd" \
        --preview-window="right:60%:wrap:border-left" \
        --preview-label=" 📋 Directory Info " \
        --print-query \
        --bind 'enter:become(echo {q})' \
        --bind 'ctrl-/:toggle-preview' \
        --bind 'ctrl-u:preview-up' \
        --bind 'ctrl-d:preview-down' \
        --bind 'ctrl-h:execute(bash -c "$(declare -f show_fzf_help); show_fzf_help"; read -n1)' \
        --bind '?:execute(bash -c "$(declare -f show_fzf_help); show_fzf_help"; read -n1)' \
        --bind 'ctrl-r:toggle-search' \
        --bind 'alt-c:toggle+clear-query' \
        --bind 'ctrl-m:execute-silent(mkdir -p {}/claude-runner 2>/dev/null)+accept' \
        --bind 'ctrl-o:execute-silent(open {} 2>/dev/null || xdg-open {} 2>/dev/null)' \
        --bind 'tab:toggle' \
        --bind 'shift-tab:toggle+up' \
        --color "header:italic:dim" \
        --color "label:blue" \
        --color "border:dim" \
        --color "preview-border:dim" \
        --color "prompt:blue:bold" \
        --color "pointer:green:bold" \
        --color "marker:yellow:bold" \
        --color "current-fg:white:bold" \
        --algo=v2 \
        --smart-case \
        --literal \
        --cycle \
        --scheme=path \
        --tiebreak=begin,length,index \
        --scroll-off=3 \
        --jump-labels='asdfghjklqwertyuiopzxcvbnm' \
        | tail -1)
    
    [[ -z "$selected" ]] && { echo "❌ No directory selected" >&2; exit 1; }
    
    # If user typed a query, try to find the best match
    if [[ "$selected" != *"/"* ]] && [[ ${#selected} -gt 2 ]]; then
        echo "🔍 Searching for directories matching '$selected'..." >&2
        
        # Find directories with names containing the search term
        local query_matches=$(echo "$projects" | while read -r path; do
            local dir_name=$(basename "$path")
            local parent_name=$(basename "$(dirname "$path")")
            local full_path_lower=$(echo "$path" | tr '[:upper:]' '[:lower:]')
            local query_lower=$(echo "$selected" | tr '[:upper:]' '[:lower:]')
            
            # Score based on match quality
            local match_score=0
            
            # Exact directory name match gets highest priority
            if [[ "$dir_name" == "$selected" ]]; then
                match_score=1000
            # Case-insensitive exact match
            elif [[ "$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')" == "$query_lower" ]]; then
                match_score=900
            # Directory name starts with query
            elif [[ "$dir_name" == "$selected"* ]]; then
                match_score=800
            elif [[ "$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')" == "$query_lower"* ]]; then
                match_score=700
            # Directory name contains query
            elif [[ "$dir_name" == *"$selected"* ]]; then
                match_score=600
            elif [[ "$(echo "$dir_name" | tr '[:upper:]' '[:lower:]')" == *"$query_lower"* ]]; then
                match_score=500
            # Parent directory name matches
            elif [[ "$parent_name" == *"$selected"* ]]; then
                match_score=300
            # Full path contains query
            elif [[ "$full_path_lower" == *"$query_lower"* ]]; then
                match_score=200
            else
                continue  # No match, skip
            fi
            
            printf "%04d:%s\n" "$match_score" "$path"
        done | sort -rn | head -10 | cut -d: -f2)
        
        if [[ -n "$query_matches" ]]; then
            echo "🎯 Found matching directories:" >&2
            echo "$query_matches" | nl -w2 -s'. ' >&2
            
            # Use the best match automatically if there's a clear winner
            local best_match=$(echo "$query_matches" | head -1)
            echo "✅ Auto-selecting best match: $best_match" >&2
            selected="$best_match"
        fi
    fi
    
    # Validate the selected path before expanding
    if ! validate_directory_path "$selected"; then
        echo "❌ Invalid directory selection" >&2
        exit 1
    fi
    
    # Expand tilde if present in user input
    local expanded_path=$(expand_tilde "$selected")
    
    # Validate the expanded path as well
    if ! validate_directory_path "$expanded_path"; then
        echo "❌ Invalid expanded directory path" >&2
        exit 1
    fi
    
    # Validate that the expanded path exists and is a directory
    if [[ ! -d "$expanded_path" ]]; then
        echo "❌ Directory does not exist: $expanded_path" >&2
        echo "💡 Available directories starting with '$(basename "$expanded_path")':" >&2
        find "$(dirname "$expanded_path")" -maxdepth 1 -type d -name "$(basename "$expanded_path")*" 2>/dev/null | head -5 >&2
        exit 1
    fi
    
    local final_path="$expanded_path/claude-runner"
    
    # Validate the final installation path
    if ! validate_directory_path "$final_path"; then
        echo "❌ Invalid final installation path" >&2
        exit 1
    fi
    
    echo "$final_path"
}

# Show help if requested
if [[ $# -gt 0 && ("$1" == "--help" || "$1" == "-h") ]]; then
    echo "Claude Runner Installer - Enhanced with Advanced FZF Directory Picker"
    echo "Usage: $0 [INSTALL_DIRECTORY]"
    echo ""
    echo "Interactive Mode Features:"
    echo "• Smart project directory discovery with scoring"
    echo "• Enhanced preview with project type detection, git status, and directory info"
    echo "• Keyboard shortcuts for navigation, search, and actions"
    echo "• Multi-select support and on-the-fly directory creation"
    echo "• Fuzzy search with path-optimized matching"
    echo "• Visual enhancements with colors and borders"
    echo ""
    echo "Key Shortcuts (Interactive Mode):"
    echo "  Ctrl+H or ?    Show help overlay"
    echo "  Ctrl+/         Toggle preview window"
    echo "  Ctrl+M         Create new directory at selection"
    echo "  Ctrl+O         Open directory in file manager"
    echo "  Tab            Multi-select toggle"
    echo ""
    echo "Requirements: docker, fzf (for interactive mode)"
    echo "Install fzf: brew install fzf (macOS) or apt install fzf (Ubuntu)"
    exit 0
fi

# Determine install directory
if [[ $# -eq 0 ]]; then
    if ! command -v fzf &> /dev/null; then
        echo "❌ ERROR: fzf not installed. Install with: brew install fzf (macOS) or apt install fzf (Ubuntu)" >&2
        echo "Or provide directory: $0 /path/to/directory" >&2
        exit 1
    fi
    INSTALL_DIR=$(pick_directory_with_fzf)
else
    # Validate command-line provided directory
    if ! validate_directory_path "$1"; then
        echo "❌ Invalid directory path provided: $1" >&2
        exit 1
    fi
    INSTALL_DIR="$1"
fi

echo "🚀 Claude Runner Installer"
echo "=========================="
echo ""
echo "Installing to: $INSTALL_DIR"
echo ""

# Check Docker availability
if ! command -v docker &> /dev/null; then
    echo "❌ ERROR: Docker not installed. Get it at: https://docs.docker.com/get-docker/" >&2
    exit 1
fi
if ! docker info &> /dev/null; then
    echo "❌ ERROR: Docker daemon not running. Please start Docker first." >&2
    exit 1
fi
echo "✅ Docker is available"

# Create directory structure
echo "📁 Creating directory structure..."

# Validate the final install directory one more time before creating
if ! validate_directory_path "$INSTALL_DIR"; then
    echo "❌ Invalid installation directory: $INSTALL_DIR" >&2
    exit 1
fi

# Attempt to create directory structure with error handling
if ! mkdir -p "$INSTALL_DIR"/{scripts,.claude/hooks} 2>/dev/null; then
    echo "❌ ERROR: Failed to create directory structure at: $INSTALL_DIR" >&2
    echo "   Check permissions and path validity" >&2
    exit 1
fi

# Copy required files from the repository
echo "📥 Installing Claude Runner files..."
if [[ -f "Dockerfile.official" && -f "scripts/save_container_auth.sh" ]]; then
    cp Dockerfile.official "$INSTALL_DIR/"
    cp scripts/*.sh "$INSTALL_DIR/scripts/"
    chmod +x "$INSTALL_DIR/scripts/"*.sh
else
    echo "❌ ERROR: Run installer from claude_runner repository directory" >&2
    echo "Or clone first: git clone https://github.com/your-username/claude_runner" >&2
    exit 1
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "📖 Quick Start:"
echo "1. cd $INSTALL_DIR"
echo "2. docker build -f Dockerfile.official -t claude-runner-official:latest ."
echo "3. docker run -it --name temp-auth claude-runner-official:latest bash"
echo "   # Inside: claude, then /login, then exit"
echo "4. ./scripts/save_container_auth.sh temp-auth && docker rm temp-auth"
echo "5. ./scripts/start_persistent_runner.sh"
echo "6. docker exec -it claude-runner bash"
echo ""
echo "🎯 Claude Code now runs in Docker with persistent auth!"