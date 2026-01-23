#!/data/data/com.termux/files/usr/bin/bash
# Made by Bisam - DEBUG VERSION

GHOSTY_VERSION="4.0.3"

# === AUTO UPDATE ===
SCRIPT_URL="https://raw.githubusercontent.com/loplocmsu-ship-it/ubiquitous-invention/refs/heads/main/termux.sh"
SCRIPT_PATH="$HOME/termux.sh"

if [ "$1" != "--no-update" ]; then
    echo "checking for updates..."
    if curl -sL "$SCRIPT_URL" -o /tmp/termux_new.sh 2>/dev/null; then
        if [ -f "$SCRIPT_PATH" ] && ! cmp -s "$SCRIPT_PATH" /tmp/termux_new.sh; then
            echo "new version found, updating..."
            cp /tmp/termux_new.sh "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            rm -f /tmp/termux_new.sh
            exec bash "$SCRIPT_PATH" --no-update
        fi
        rm -f /tmp/termux_new.sh
    fi
fi
# === END AUTO UPDATE ===

set -o pipefail

RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
NC='\033[0m'

dbg() { echo -e "${BLU}[DBG]${NC} $1"; }
ok() { echo -e "${GRN}[OK]${NC} $1"; }
warn() { echo -e "${YLW}[WARN]${NC} $1"; }
die() { echo -e "${RED}[FATAL]${NC} $1"; echo "--- crash log: ~/ghosty_crash.log ---"; exit 1; }

get_zip_version() {
    local v=$(echo "$1" | grep -oE 'V?[0-9]+\.[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    if [ -z "$v" ]; then
        v=$(echo "$1" | grep -oE 'V?[0-9]+\.[0-9]+' | grep -oE '[0-9]+\.[0-9]+' | head -1)
        [ -n "$v" ] && v="$v.0"
    fi
    echo "$v"
}

ver_compare() {
    [ "$1" = "$2" ] && return 1
    local IFS=.
    local i v1=($1) v2=($2)
    for ((i=0; i<3; i++)); do
        [ "${v1[i]:-0}" -gt "${v2[i]:-0}" ] && return 0
        [ "${v1[i]:-0}" -lt "${v2[i]:-0}" ] && return 2
    done
    return 1
}

# checks if token is placeholder or invalid
is_placeholder_token() {
    local t="$1"
    [ -z "$t" ] && return 0
    [ "$t" = "YOUR_TOKEN_HERE" ] && return 0
    [ "$t" = "Add your token here" ] && return 0
    [[ "${t,,}" == *"your token"* ]] && return 0
    [[ "${t,,}" == *"token here"* ]] && return 0
    [[ "${t,,}" == *"add token"* ]] && return 0
    [[ "${t,,}" == *"enter token"* ]] && return 0
    [[ "${t,,}" == *"put token"* ]] && return 0
    # real tokens are 70+ chars
    [ ${#t} -lt 50 ] && return 0
    return 1
}

exec > >(tee -a ~/ghosty_crash.log) 2>&1
echo "=== RUN $(date) ===" >> ~/ghosty_crash.log

clear
echo "=== GhoSty OwO Auto Setup v$GHOSTY_VERSION ==="
echo "    Made by Bisam (debug mode)"
echo ""

dbg "checking environment..."
[ ! -d "/data/data/com.termux" ] && die "not running in termux"
ok "termux env detected"

dbg "termux-exec status:"
if [ -f "/data/data/com.termux/files/usr/lib/libtermux-exec.so" ]; then
    ok "termux-exec found"
else
    warn "termux-exec missing"
fi

dbg "checking storage..."
if [ ! -L "$HOME/storage/downloads" ] || [ ! -d "$HOME/storage/shared" ]; then
    warn "storage not linked"
    echo ">>> PRESS ALLOW WHEN POPUP SHOWS <<<"
    termux-setup-storage
    ret=$?
    [ $ret -ne 0 ] && warn "termux-setup-storage returned $ret"
    sleep 3
    [ -d "$HOME/storage" ] && ok "storage created" || warn "storage not accessible"
else
    ok "storage configured"
fi

dbg "checking tools..."
missing=()
for tool in unzip curl sed grep find; do
    command -v $tool &>/dev/null && ok "$tool found" || { warn "$tool missing"; missing+=($tool); }
done

if [ ${#missing[@]} -gt 0 ]; then
    dbg "installing: ${missing[*]}"
    pkg update -y 2>&1 | tail -3
    for t in "${missing[@]}"; do
        pkg install -y $t || die "failed to install $t"
    done
fi

ghosty_home="$HOME/ghosty"
version_file="$ghosty_home/.ghosty_version"
dbg "ghosty_home = $ghosty_home"

installed_version=""
need_install=0
is_upgrade=0

if [ -f "$version_file" ]; then
    installed_version=$(cat "$version_file")
    dbg "installed: v$installed_version"
    
    ver_compare "$GHOSTY_VERSION" "$installed_version"
    case $? in
        0) 
            warn "update available: v$installed_version -> v$GHOSTY_VERSION"
            need_install=1
            is_upgrade=1
            ;;
        1) ok "already v$GHOSTY_VERSION" ;;
        2) ok "v$installed_version is newer, skipping" ;;
    esac
elif [ -d "$ghosty_home" ] && [ -f "$ghosty_home/config.json" ]; then
    warn "old install without version tracking"
    need_install=1
    is_upgrade=1
else
    dbg "fresh install"
    need_install=1
fi

if [ $need_install -eq 1 ]; then
    paths=(
        "/storage/emulated/0/Download"
        "/storage/emulated/0"
        "/sdcard/Download"
        "/sdcard"
        "$HOME/storage/downloads"
        "$HOME/storage/shared/Download"
        "$HOME"
        "$(pwd)"
    )
    
    zipfile=""
    foundpath=""
    zip_version=""
    found_other=""
    found_other_ver=""
    
    dbg "searching for v$GHOSTY_VERSION zip (including subfolders)..."
    
    check_zip() {
        local zf="$1"
        [ ! -f "$zf" ] && return 1
        
        local tmp_zip=$(basename "$zf")
        local tmp_ver=$(get_zip_version "$tmp_zip")
        local tmp_dir=$(dirname "$zf")
        dbg "found: $zf -> v$tmp_ver"
        
        if [ "$tmp_ver" = "$GHOSTY_VERSION" ]; then
            zipfile="$tmp_zip"
            foundpath="$tmp_dir"
            zip_version="$tmp_ver"
            ok "matched v$zip_version"
            return 0
        else
            found_other="$tmp_zip"
            found_other_ver="$tmp_ver"
            warn "wrong version: need v$GHOSTY_VERSION, found v$tmp_ver"
            return 1
        fi
    }
    
    for p in "${paths[@]}"; do
        [ ! -d "$p" ] && continue
        dbg "checking: $p"
        
        for zf in "$p"/GhoSty*OwO*.zip "$p"/ghosty*.zip "$p"/Ghosty*.zip; do
            check_zip "$zf" && break 2
        done
        
        while IFS= read -r -d '' zf; do
            check_zip "$zf" && break 2
        done < <(find "$p" -maxdepth 3 -type f \( -iname "GhoSty*OwO*.zip" -o -iname "ghosty*.zip" \) -print0 2>/dev/null)
        
        [ -n "$foundpath" ] && break
    done
    
    if [ -z "$foundpath" ]; then
        echo ""
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if [ $is_upgrade -eq 1 ]; then
            echo -e "${RED}  UPDATE REQUIRED: v$installed_version -> v$GHOSTY_VERSION${NC}"
        else
            echo -e "${RED}  VERSION MISMATCH${NC}"
        fi
        echo -e "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        if [ -n "$found_other" ]; then
            echo "  Found: $found_other (v$found_other_ver)"
            echo "  Need:  v$GHOSTY_VERSION"
            echo ""
        fi
        echo "  Please download: GhoSty OwO V${GHOSTY_VERSION}.zip"
        echo "  Put it in your Downloads folder (or any subfolder)"
        echo ""
        echo "  Then run this script again"
        echo ""
        die "zip v$GHOSTY_VERSION not found"
    fi
    
    old_token=""
    if [ -f "$ghosty_home/config.json" ]; then
        old_token=$(grep -o '"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' "$ghosty_home/config.json" | cut -d'"' -f4)
        # dont backup if its a placeholder
        is_placeholder_token "$old_token" && old_token=""
        [ -n "$old_token" ] && dbg "backed up token"
    fi
    
    rm -rf "$ghosty_home"
    cd "$foundpath" || die "can't cd to $foundpath"
    
    tmpextract="$HOME/ghosty_tmp"
    rm -rf "$tmpextract"
    mkdir -p "$tmpextract" || die "can't create temp dir"
    
    dbg "extracting $zipfile from $foundpath..."
    unzip -o "$zipfile" -d "$tmpextract"
    [ $? -ne 0 ] && die "unzip failed"
    ok "extracted"
    
    contents=$(ls -A "$tmpextract")
    count=$(echo "$contents" | wc -l)
    first=$(echo "$contents" | head -1)
    dbg "items: $count, first: $first"
    
    if [ $count -eq 1 ] && [ -d "$tmpextract/$first" ]; then
        mv "$tmpextract/$first" "$ghosty_home"
    else
        mv "$tmpextract" "$ghosty_home"
    fi
    rm -rf "$tmpextract"
    
    echo "$zip_version" > "$ghosty_home/.ghosty_version"
    
    if [ $is_upgrade -eq 1 ]; then
        ok "upgraded to v$zip_version"
    else
        ok "installed v$zip_version"
    fi
    
    if [ -n "$old_token" ]; then
        # handle both old and new placeholder formats
        sed -i "s/YOUR_TOKEN_HERE/$old_token/g; s/Add your token here/$old_token/g" "$ghosty_home/config.json" 2>/dev/null
        ok "token restored"
    fi
fi

cd "$ghosty_home" || die "can't cd to $ghosty_home"
[ ! -f "config.json" ] && die "config.json missing"

current_ver=$(cat "$version_file" 2>/dev/null || echo "unknown")
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  GhoSty OwO v$current_ver"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"

dbg "config preview:"
cat config.json | sed 's/"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"/"TOKEN": "***"/g' | head -15

token_val=$(grep -o '"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' config.json | cut -d'"' -f4)
dbg "token: ${token_val:0:10}..."

if is_placeholder_token "$token_val"; then
    echo ""
    read -p "Enter Discord token: " tok
    [ -z "$tok" ] && die "empty token"
    
    dbg "token length: ${#tok}"
    [[ ! "$tok" =~ ^[A-Za-z0-9._-]+$ ]] && warn "token has weird chars"
    
    dbg "validating with discord..."
    resp=$(curl -s -w "%{http_code}" \
        -H "Authorization: $tok" \
        https://discord.com/api/v10/users/@me -o /dev/null)
    
    dbg "http: $resp"
    
    case "$resp" in
        200)
            ok "token valid"
            cp config.json config.json.bak
            tok_escaped=$(printf '%s\n' "$tok" | sed -e 's/[\/&]/\\&/g')
            # replace both placeholder formats
            sed -i "s/YOUR_TOKEN_HERE/$tok_escaped/g; s/Add your token here/$tok_escaped/g" config.json
            # fallback if sed didnt work (some edge case)
            if is_placeholder_token "$(grep -o '"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' config.json | cut -d'"' -f4)"; then
                dbg "sed failed, using python..."
                python3 -c "
import json
with open('config.json','r') as f: c=json.load(f)
c['TOKEN']='$tok'
with open('config.json','w') as f: json.dump(c,f,indent=4)"
            fi
            ok "config updated"
            ;;
        401) die "token invalid (401)" ;;
        403) die "token forbidden (403)" ;;
        429) die "rate limited (429)" ;;
        000) die "network error - check internet" ;;
        *) die "unexpected: $resp" ;;
    esac
else
    ok "token already set"
fi

dbg "installing packages..."
for p in python python-pillow python-numpy; do
    dpkg -s $p &>/dev/null && ok "$p ok" || pkg install -y $p 2>&1 | tail -3
done

command -v pip &>/dev/null || pkg install -y python-pip
ok "pip: $(pip --version 2>&1 | head -1)"

[ -f "requirements.txt" ] && { dbg "pip requirements..."; pip install -r requirements.txt 2>&1 | tail -8; }

echo ""
dbg "python: $(python --version 2>&1)"
dbg "pwd: $(pwd)"
[ ! -f "main.py" ] && die "main.py not found"

echo "starting bot..."
sleep 1
python main.py
py_ret=$?
[ $py_ret -ne 0 ] && die "python exited with code $py_ret"
