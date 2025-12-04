# ============================= GitHub Commands ===============================
# Create a public GitHub repository
function ghpu
    set repo_name $argv[1]
    
    # If no repository name provided, use current directory name
    if test -z "$repo_name"
        set repo_name (basename (pwd))
    end
    
    echo "Creating public repository: $repo_name"
    
    # Initialize and push to GitHub
    git init || return 1
    
    # Create public repository on GitHub (requires GitHub CLI)
    if command -sq gh
        gh repo create $repo_name --public --source=. --remote=origin || return 1
    else
        # Fallback if GitHub CLI is not available
        git remote add origin https://github.com/isaaclins/$repo_name.git || return 1
        echo "Note: Install GitHub CLI (gh) for better repository creation experience"
    end
    
    # Check if directory is empty
    set file_count (ls -A | wc -l | string trim)
    if test "$file_count" = "1" -a -d ".git"
        # Only .git directory exists - create README
        echo "# $repo_name " > README.md
    end
    
    git add . || return 1
    
    # Check if there are changes to commit
    if git status --porcelain | grep -q "^[MADRCU]"
        git commit -m "Initial commit" || return 1
    else
        # Create an empty commit if there are no files to commit
        git commit --allow-empty -m "Initial commit" || return 1
    end
    
    # Get current branch name
    set current_branch (git branch --show-current)
    if test -z "$current_branch"
        set current_branch "main" # Default to main if branch name can't be determined
    end
    
    git push -u origin $current_branch || return 1
    
    return 0
end

# Create a private GitHub repository
function ghpr
    set repo_name $argv[1]
    
    # If no repository name provided, use current directory name
    if test -z "$repo_name"
        set repo_name (basename (pwd))
    end
    
    echo "Creating private repository: $repo_name"
    
    # Initialize and push to GitHub
    git init || return 1
    
    # Create private repository on GitHub (requires GitHub CLI)
    if command -sq gh
        gh repo create $repo_name --private --source=. --remote=origin || return 1
    else
        # Fallback if GitHub CLI is not available
        git remote add origin https://github.com/isaaclins/$repo_name.git || return 1
        echo "Note: Install GitHub CLI (gh) for better repository creation experience"
    end
    
    # Check if directory is empty
    set file_count (ls -A | wc -l | string trim)
    if test "$file_count" = "1" -a -d ".git"
        # Only .git directory exists - create README
        echo "# $repo_name " > README.md
    end
    
    git add . || return 1
    
    # Check if there are changes to commit
    if git status --porcelain | grep -q "^[MADRCU]"
        git commit -m "Initial commit" || return 1
    else
        # Create an empty commit if there are no files to commit
        git commit --allow-empty -m "Initial commit" || return 1
    end
    
    # Get current branch name
    set current_branch (git branch --show-current)
    if test -z "$current_branch"
        set current_branch "main" # Default to main if branch name can't be determined
    end
    
    git push -u origin $current_branch || return 1
    
    return 0
end

# Git Random Commit 
function grc 
    git commit -m (curl -s https://whatthecommit.com/index.txt)
end

# Git Random Push
function grp
    git add .
    git commit -m (curl -s https://whatthecommit.com/index.txt)
    git push origin (git branch --show-current)
end

# Create a new public project
function npu
    set original_dir (pwd)
    set success 1
    
    cd ~/Documents/github/ || return 1
    
    if test -d $argv[1]
        echo "Error: Directory $argv[1] already exists"
        cd $original_dir
        return 1
    end
    
    mkdir $argv[1] && cd $argv[1] || begin
        echo "Error: Failed to create directory $argv[1]"
        cd $original_dir
        return 1
    end
    
    if not ghpu
        echo "Error: Repository creation failed. Cleaning up..."
        cd $original_dir
        rm -rf ~/Documents/github/$argv[1]
        
        # If the repo was created on GitHub but local setup failed, try to delete it
        if command -sq gh
            gh repo delete isaaclins/$argv[1] --yes 2>/dev/null
        end
        
        return 1
    end
    
    echo "Project successfully created: $argv[1]"
    
    # Open Cursor IDE at the current directory
    if command -sq cursor
        open -a 'Cursor' .
    else
        # Try alternative methods
        if command -sq open
            open -a 'Cursor' .
        end
    end
    
    return 0
end

# Create a new private project
function npr
    set original_dir (pwd)
    set success 1
    
    cd ~/Documents/github/ || return 1
    
    if test -d $argv[1]
        echo "Error: Directory $argv[1] already exists"
        cd $original_dir
        return 1
    end
    
    mkdir $argv[1] && cd $argv[1] || begin
        echo "Error: Failed to create directory $argv[1]"
        cd $original_dir
        return 1
    end
    
    if not ghpr
        echo "Error: Repository creation failed. Cleaning up..."
        cd $original_dir
        rm -rf ~/Documents/github/$argv[1]
        
        # If the repo was created on GitHub but local setup failed, try to delete it
        if command -sq gh
            gh repo delete isaaclins/$argv[1] --yes 2>/dev/null
        end
        
        return 1
    end
    
    echo "Project successfully created: $argv[1]"
    
    # Open Cursor IDE at the current directory
    if command -sq cursor
        open -a 'Cursor' .
    else
        # Try alternative methods
        if command -sq open
            open -a 'Cursor' .
        end
    end
    
    return 0
end

function kp
    if test (count $argv) -eq 0
        echo "Usage: kp <port>"
        return 1
    end

    set port $argv[1]
    set pids (lsof -ti tcp:$port)

    if test -z "$pids"
        echo "No process found using port $port."
        return 0
    end

    for pid in $pids
        echo "Killing process $pid using port $port..."
        kill -9 $pid
    end
end

function grcp 
    git commit -m (curl -s https://whatthecommit.com/index.txt)
    git push origin (git branch --show-current)
end

function copy
    pbcopy
    echo "Copied to clipboard"
end


function cports
    # Use provided IP/domain or default to localhost
    if test (count $argv) -gt 0
        set ip_address $argv[1]
    else
        set ip_address "127.0.0.1"
    end
    
    echo "Scanning ports on $ip_address..."

    # Run rustscan and filter only the summary lines
    set results (rustscan -a $ip_address -r 1-65535 --ulimit 65535 $extra_args | grep -E '^[0-9]+/tcp\s+open')

    # Print table header
    printf "| %-6s | %-8s | %-15s |\n" "port" "protocol" "service"
    printf "|-%-6s-|-%-8s-|-%-15s-|\n" "------" "--------" "---------------"

    # Print each result in table format
    for line in $results
        # Split the line into fields
        set port_proto (echo $line | awk '{print $1}')
        set port (echo $port_proto | cut -d'/' -f1)
        set proto (echo $port_proto | cut -d'/' -f2)
        set service (echo $line | awk '{print $3}')
        if test -z "$service"
            set service "unknown"
        end
        printf "| %-6s | %-8s | %-15s |\n" $port $proto $service
    end
end

function initdocker
    set -l packages
    set -l copy_paths
    set -l mount_mode 0
    set -l container_name
    set -l prefix "initdocker-"
    set -l purge_mode 0
    set -l cpu_limit "1.0"
    set -l memory_limit "1g"
    set -l pids_limit "256"
    set -l read_only 0
    set -l no_net 0

    set -l argv_copy $argv
    while test (count $argv_copy) -gt 0
        set arg $argv_copy[1]
        set -e argv_copy[1]

        switch $arg
            case '-h' '--help'
                echo "Usage: initdocker [options]"
                echo ""
                echo "Options:"
                echo "  -p <pkg1 pkg2 ...>         Install all listed Homebrew packages"
                echo "  -c <file/dir>              Copy host path/file into container (repeatable)"
                echo "  -m                         Mount provided -c paths live instead of copying"
                echo "  -n|--name <name>           Use explicit container name (default: random)"
                echo "  --prefix <text>            Prefix for random container names (default: initdocker-)"
                echo "  --purge                    Stop/remove all containers with current prefix"
                echo "  --no-net                   Disable networking (docker --network none)"
                echo "  --memory <limit>           Memory limit (default: 1g)"
                echo "  --cpus <num>               CPU limit (default: 1.0)"
                echo "  --pids-limit <num>         PIDs limit (default: 256)"
                echo "  --read-only                Read-only root FS"
                echo "  --writable                 Writable root FS (default)"
                echo "  -h                         Display this help and exit"
                echo ""
                echo "Default: builds image and starts a shell in a container named \"$prefix<random>\"."
                return 0
            case '-p' '--package'
                # Collect all subsequent non-flag arguments as packages
                if test (count $argv_copy) -eq 0
                    echo "Error: -p requires at least one package" >&2
                    return 1
                end
                while test (count $argv_copy) -gt 0
                    set next $argv_copy[1]
                    if string match -qr '^-' -- $next
                        break
                    end
                    set -a packages $next
                    set -e argv_copy[1]
                end
                if test (count $packages) -eq 0
                    echo "Error: -p requires at least one package" >&2
                    return 1
                end
            case '-c' '--copy'
                if test (count $argv_copy) -gt 0
                    set next $argv_copy[1]
                    if string match -qr '^-' -- $next
                        echo "Error: -c requires a file or directory path" >&2
                        return 1
                    end
                    set -a copy_paths $next
                    set -e argv_copy[1]
                else
                    echo "Error: -c requires a file or directory path" >&2
                    return 1
                end
            case '-m' '--mount'
                set mount_mode 1
            case '-n' '--name'
                if test (count $argv_copy) -gt 0
                    set container_name $argv_copy[1]
                    set -e argv_copy[1]
                else
                    echo "Error: --name requires a value" >&2
                    return 1
                end
            case '--prefix'
                if test (count $argv_copy) -gt 0
                    set prefix $argv_copy[1]
                    set -e argv_copy[1]
                else
                    echo "Error: --prefix requires a value" >&2
                    return 1
                end
            case '--purge'
                set purge_mode 1
            case '--no-net'
                set no_net 1
            case '--read-only'
                set read_only 1
            case '--writable'
                set read_only 0
            case '--memory'
                if test (count $argv_copy) -gt 0
                    set memory_limit $argv_copy[1]
                    set -e argv_copy[1]
                else
                    echo "Error: --memory requires a value (e.g., 1g, 512m)" >&2
                    return 1
                end
            case '--cpus'
                if test (count $argv_copy) -gt 0
                    set cpu_limit $argv_copy[1]
                    set -e argv_copy[1]
                else
                    echo "Error: --cpus requires a value (e.g., 1.0)" >&2
                    return 1
                end
            case '--pids-limit'
                if test (count $argv_copy) -gt 0
                    set pids_limit $argv_copy[1]
                    set -e argv_copy[1]
                else
                    echo "Error: --pids-limit requires a numeric value" >&2
                    return 1
                end
            case '*'
                echo "Error: Unknown option $arg" >&2
                return 1
        end
    end

    # Preflight: ensure Docker is available and the daemon is running
    if not command -sq docker
        echo "❌ Docker is not installed or not in PATH"
        return 1
    end
    docker info >/dev/null 2>&1
    if test $status -ne 0
        echo "❌ Docker daemon is not running. Please start Docker Desktop."
        return 1
    end

    # Purge mode: stop/remove all containers with matching prefix, then exit
    if test $purge_mode -eq 1
        set -l all_names (docker ps -a --format '{{.Names}}')
        set -l to_purge
        for n in $all_names
            if test (string length -- $n) -ge (string length -- $prefix)
                if test (string sub -s 1 -l (string length -- $prefix) -- $n) = $prefix
                    set -a to_purge $n
                end
            end
        end
        if test (count $to_purge) -eq 0
            echo "No containers found with prefix '$prefix'"
            return 0
        end
        echo "Purging containers with prefix '$prefix':" (string join ' ' $to_purge)
        for n in $to_purge
            docker rm -f $n >/dev/null 2>&1
        end
        echo "✅ Purge complete"
        return 0
    end

    # Validate read-only mode vs copy behavior
    if test $read_only -eq 1 -a $mount_mode -eq 0 -a (count $copy_paths) -gt 0
        echo "❌ --read-only is incompatible with copying files after start. Use -m to mount the paths or pass --writable." >&2
        return 1
    end

    # Determine container name (random by default)
    if test -z "$container_name"
        set -l rand (uuidgen | tr -d '-' | string lower | string sub -s 1 -l 8)
        set container_name "$prefix$rand"
    end

    # Validate copy/mount paths early
    if test (count $copy_paths) -gt 0
        for path in $copy_paths
            if not test -e $path
                echo "❌ Path not found: $path" >&2
                return 1
            end
        end
    end

    # Build Docker image from inline Dockerfile (stdin) using ~/.config/fish as context
    set -l context_dir "$HOME/.config/fish"
    set -l uid (id -u)
    set -l gid $uid

    set -l dockerfile_lines
    set -a dockerfile_lines 'FROM debian:bookworm-slim'
    set -a dockerfile_lines 'RUN apt-get update && apt-get install -y fish git curl ca-certificates procps file --no-install-recommends && apt-get clean && rm -rf /var/lib/apt/lists/*'
    set -a dockerfile_lines 'ARG USER_UID=1000'
    set -a dockerfile_lines 'ARG USER_GID=$USER_UID'
    set -a dockerfile_lines 'RUN groupadd --gid $USER_GID docker-dev && useradd --uid $USER_UID --gid $USER_GID -m docker-dev && chsh -s /usr/bin/fish docker-dev'
    set -a dockerfile_lines 'WORKDIR /home/docker-dev'
    set -a dockerfile_lines 'COPY . .config/fish'
    set -a dockerfile_lines 'RUN chown -R docker-dev:docker-dev .config'
    set -a dockerfile_lines 'RUN mkdir -p /home/linuxbrew && chown -R docker-dev:docker-dev /home/linuxbrew'
    set -a dockerfile_lines 'USER docker-dev'
    set -a dockerfile_lines 'ENV SHELL=/usr/bin/fish'
    set -a dockerfile_lines 'ENV PATH="/home/linuxbrew/.linuxbrew/bin:/home/linuxbrew/.linuxbrew/sbin:/home/docker-dev/.cargo/bin:${PATH}"'
    set -a dockerfile_lines 'ENV HOMEBREW_NO_AUTO_UPDATE=1'
    set -a dockerfile_lines 'ENV HOMEBREW_PREFIX=/home/linuxbrew/.linuxbrew'
    set -a dockerfile_lines 'ENV HOMEBREW_CELLAR=/home/linuxbrew/.linuxbrew/Cellar'
    set -a dockerfile_lines 'RUN git clone --depth 1 https://github.com/Homebrew/brew.git /home/linuxbrew/.linuxbrew'
    if test (count $packages) -gt 0
        set packages_str (string join " " $packages)
        set -a dockerfile_lines "RUN /home/linuxbrew/.linuxbrew/bin/brew install $packages_str"
    end
    set -a dockerfile_lines 'RUN mkdir -p .config/fish/conf.d && printf '%s\\n' '\''eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"'\'' '\''set -gx HOMEBREW_PREFIX /home/linuxbrew/.linuxbrew'\'' '\''set -gx HOMEBREW_CELLAR /home/linuxbrew/.linuxbrew/Cellar'\'' > .config/fish/conf.d/brew.fish'
    set -a dockerfile_lines 'SHELL ["/usr/bin/fish", "-l", "-c"]'
    set -a dockerfile_lines 'CMD ["fish"]'

    echo "📦 Building image..."
    printf '%s\n' $dockerfile_lines | docker build --network=host --build-arg USER_UID=$uid --build-arg USER_GID=$gid -t fish-dev -f - "$context_dir"
    if test $status -ne 0
        echo "❌ docker build failed"
        return 1
    end

    echo "🧹 Ensuring old container is removed (if exists): $container_name"
    docker rm -f $container_name >/dev/null 2>&1

    set -l run_cmd "docker run --rm -d --name $container_name"
    if test $no_net -eq 1
        set run_cmd "$run_cmd --network none"
    end
    set run_cmd "$run_cmd --pids-limit $pids_limit --memory $memory_limit --cpus $cpu_limit"
    if test $read_only -eq 1
        set run_cmd "$run_cmd --read-only"
    end
    if test $mount_mode -eq 1 -a (count $copy_paths) -gt 0
        for path in $copy_paths
            # Portable absolute path resolution (macOS compatible)
            set abspath (begin; set dir (dirname $path); set base (basename $path); cd $dir 2>/dev/null; and echo (pwd)/$base; end)
            set bname (basename $path)
            set run_cmd "$run_cmd -v \"$abspath\":\"/home/docker-dev/$bname\""
        end
    end
    set run_cmd "$run_cmd fish-dev sleep infinity"
    echo "🚀 Starting container..."
    eval $run_cmd
    if test $status -ne 0
        echo "❌ docker run failed"
        return 1
    end

    if test $mount_mode -eq 0 -a (count $copy_paths) -gt 0
        echo "📁 Copying files into container..."
        for path in $copy_paths
            # Portable absolute path resolution (macOS compatible)
            set abspath (begin; set dir (dirname $path); set base (basename $path); cd $dir 2>/dev/null; and echo (pwd)/$base; end)
            set bname (basename $path)
            docker cp "$abspath" $container_name:"/home/docker-dev/$bname"
            if test $status -ne 0
                echo "❌ docker cp failed for $abspath"
                return 1
            end
            docker exec $container_name chown -R docker-dev:docker-dev "/home/docker-dev/$bname"
        end
    end

    echo "🔧 Opening shell inside container..."
    docker exec -it $container_name fish
    set -l shell_status $status
    echo "🛑 Stopping container..."
    docker stop $container_name >/dev/null 2>&1
    return $shell_status
end


function yt2txt
    if test (count $argv) -lt 1
        echo "Usage: transcribe-yt <youtube-url> "
        return 1
    end
    mkdir -p (pwd)/transcription
    set -l UUID (uuidgen)
    echo $UUID
    set -l tmp_dir (pwd)/$UUID
    echo $tmp_dir
    mkdir -p $tmp_dir
    set url $argv[1]
    cd $tmp_dir

    transcribe-anything $url --device cpu 

    cd "$(ls -d */ | head -n 1)"
    cp out.txt ../../transcription/out.txt
    echo FINAL DIRECTORY: (pwd)
    rm -rf $tmp_dir
    echo "================================================"
    echo "         🚀 Transcription completed."
    echo "================================================"
end

function setjava 
    if test (count $argv) -lt 1
        echo "Usage: setjava <version>"
        echo "Example: setjava 17, setjava 21, etc."
        return 1
    end
    
    set java_version $argv[1]
    
    # Check if argument is a number
    if not string match -qr '^\d+$' -- $java_version
        echo "❌ Error: Version must be a number (e.g., 17, 21)"
        return 1
    end
    
    # Check if Java version is installed and linked via Homebrew
    set java_path "/opt/homebrew/opt/openjdk@$java_version"
    set is_installed (brew list openjdk@$java_version 2>/dev/null)
    
    if not test -d $java_path
        if test -n "$is_installed"
            # Installed but not linked
            echo "⚠️  Java $java_version is installed but not linked."
            echo "🔗 Linking OpenJDK $java_version..."
            if not brew link openjdk@$java_version 2>/dev/null
                # Try with --force if regular link fails
                if not brew link --force openjdk@$java_version 2>/dev/null
                    echo "❌ Failed to link OpenJDK $java_version"
                    echo "Try running: sudo ln -sfn /opt/homebrew/opt/openjdk@$java_version/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-$java_version.jdk"
                    return 1
                end
            end
            echo "✅ OpenJDK $java_version linked successfully"
        else
            # Not installed at all
            echo "⚠️  Java $java_version is not installed via Homebrew."
            echo -n "Would you like to install it? [y/N]: "
            echo ""
            echo "================================================"
            read -l response
            echo "================================================"
            if test "$response" = "y" -o "$response" = "Y" -o "$response" = "yes"
                echo "📦 Installing OpenJDK $java_version..."
                if not brew install openjdk@$java_version
                    echo "❌ Failed to install OpenJDK $java_version"
                    return 1
                end
                echo "✅ OpenJDK $java_version installed successfully"
                # Auto-link after install
                echo "🔗 Linking OpenJDK $java_version..."
                brew link openjdk@$java_version 2>/dev/null
                or brew link --force openjdk@$java_version 2>/dev/null
            else
                echo "❌ Installation cancelled"
                return 1
            end
        end
    end
    
    # Set JAVA_HOME
    set -gx JAVA_HOME "$java_path/libexec/openjdk.jdk/Contents/Home"
    
    # Clean PATH of other OpenJDK versions
    set -l clean_path
    for dir in (string split : $PATH)
        if not string match -qr "/openjdk@\d+/" -- $dir
            set clean_path $clean_path $dir
        end
    end
    
    # Set new PATH with selected Java version
    set -gx PATH $JAVA_HOME/bin $clean_path
    
    echo "✅ Switched to Java $java_version (Homebrew)"
    which java
    java -version
end

function md2pdf
    if test (count $argv) -lt 1
        echo "Usage: md2pdf INPUT.md [OUTPUT.pdf]"
        return 1
    end

    set -l in $argv[1]
    if not test -e "$in"
        echo "File not found: $in"
        return 1
    end

    if test (count $argv) -ge 2
        set -l out $argv[2]
    else
        set -l dir (path dirname $in)
        set -l stem (string replace -r '\.md$' '' (path basename $in))
        set -l out "$dir/$stem.pdf"
    end

    if not type -q mermaid-filter
        echo "Missing mermaid-filter. Install: npm i -g mermaid-filter @mermaid-js/mermaid-cli"
        return 1
    end

    if not set -q PUPPETEER_EXECUTABLE_PATH
        if test -x "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
            set -x PUPPETEER_EXECUTABLE_PATH "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        end
    end

    set -x MERMAID_FILTER_FORMAT png

    pandoc "$in" -o "$out" \
        --pdf-engine=xelatex -V mainfont="Helvetica Neue" \
        --filter mermaid-filter
        

    if test $status -ne 0
        echo "xelatex failed, retrying with lualatex..."
        pandoc "$in" -o "$out" \
            --pdf-engine=lualatex \
            --filter mermaid-filter
    end
end

function toggle
    if test (count $argv) -eq 0
        echo "Usage: toggle <directory>"
        return 1
    end

    set dir $argv[1]

    # Check owner
    set owner (stat -f "%Su" $dir)

    if test $owner = (whoami)
        # Owned by user → lock it
        sudo chown root:wheel $dir
        sudo chmod 700 $dir
        echo "🔒 Locked $dir (root-only access)."
    else
        # Otherwise → unlock it
        sudo chown (whoami):staff $dir
        sudo chmod 700 $dir
        echo "🔓 Unlocked $dir (owned by "(whoami)")."
    end
end


function copy_last_output
    # Parse the session log, grab the last block after a prompt
    awk '
    /^┌─\[.*\]─/ { block=""; next }
    { block = block $0 ORS }
    END { printf "%s", block }
    ' /tmp/fish_session.log | pbcopy
end

function __fish_history_up_fix
    # Save cursor position, move up 2 lines (prompt height), clear everything below, restore, then navigate
    printf '\e7'        # Save cursor position
    printf '\e[2A'      # Move up 2 lines (your prompt is 2 lines)
    printf '\e[J'       # Clear from cursor to end of screen
    printf '\e8'        # Restore cursor position
    commandline -f history-search-backward
    commandline -f force-repaint
end

function __fish_history_down_fix
    # Save cursor position, move up 2 lines (prompt height), clear everything below, restore, then navigate
    printf '\e7'        # Save cursor position
    printf '\e[2A'      # Move up 2 lines (your prompt is 2 lines)
    printf '\e[J'       # Clear from cursor to end of screen
    printf '\e8'        # Restore cursor position
    commandline -f history-search-forward
    commandline -f force-repaint
end

function fish_user_key_bindings
    bind super-shift-c copy_last_output
    # Fix multi-line command history rendering with full screen repaint
    bind \e\[A __fish_history_up_fix
    bind \e\[B __fish_history_down_fix
end

function fff
    while true
        clear
        fastfetch
        sleep 1
    end
end
function pdf2shots
    if test (count $argv) -lt 1
        echo "Usage: pdf2shots <pdf-file> [output-dir] [--combine]"
        return 1
    end

    set pdf $argv[1]
    if not test -f $pdf
        echo "Error: File '$pdf' not found"
        return 1
    end

    set outdir (or $argv[2] (basename $pdf .pdf))
    set combine (contains --combine $argv)
    mkdir -p $outdir

    echo "Converting $pdf → $outdir/page-*.png ..."
    magick -density 300 "$pdf" -quality 100 "$outdir/page-%03d.png"

    if test $status -ne 0
        echo "❌ Conversion failed."
        return 1
    end

    if test $combine = 1
        set combined "$outdir/combined.png"
        echo "Combining all pages into one tall image..."
        magick "$outdir/page-*.png" -append "$combined"

        if test $status -eq 0
            echo "✅ Combined image saved as: $combined"
        else
            echo "❌ Failed to combine images."
        end
    else
        echo "✅ Individual page images saved in: $outdir/"
    end
end
