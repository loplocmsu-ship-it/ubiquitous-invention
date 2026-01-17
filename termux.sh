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
    echo "$1" | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1
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
for tool in unzip curl sed grep; do
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

# check installed version
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

# install/upgrade
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
    
    dbg "searching for zip..."
    for p in "${paths[@]}"; do
        [ ! -d "$p" ] && continue
        dbg "checking: $p"
        for zf in "$p"/GhoSty*OwO*.zip "$p"/ghosty*.zip "$p"/Ghosty*.zip; do
            if [ -f "$zf" ]; then
                tmp_zip=$(basename "$zf")
                tmp_ver=$(get_zip_version "$tmp_zip")
                dbg "found: $tmp_zip (v$tmp_ver)"
                
                # check if this zip matches required version
                if [ "$tmp_ver" = "$GHOSTY_VERSION" ]; then
                    zipfile="$tmp_zip"
                    foundpath="$p"
                    zip_version="$tmp_ver"
                    ok "matched: v$zip_version"
                    break 2
                else
                    dbg "skipping: need v$GHOSTY_VERSION, found v$tmp_ver"
                fi
            fi
        done
    done
    
    # no matching zip found
    if [ -z "$foundpath" ]; then
        echo ""
        echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        if [ $is_upgrade -eq 1 ]; then
            echo -e "${YLW}  UPDATE REQUIRED: v$installed_version -> v$GHOSTY_VERSION${NC}"
        else
            echo -e "${YLW}  INSTALL REQUIRED: v$GHOSTY_VERSION${NC}"
        fi
        echo -e "${YLW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
        echo ""
        echo "  Please download: GhoSty_OwO_V${GHOSTY_VERSION}.zip"
        echo "  Put it in your Downloads folder"
        echo ""
        echo "  Then run this script again"
        echo ""
        die "zip v$GHOSTY_VERSION not found"
    fi
    
    # backup token
    old_token=""
    if [ -f "$ghosty_home/config.json" ]; then
        old_token=$(grep -o '"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' "$ghosty_home/config.json" | cut -d'"' -f4)
        [ "$old_token" = "YOUR_TOKEN_HERE" ] && old_token=""
        [ -n "$old_token" ] && dbg "backed up token"
    fi
    
    rm -rf "$ghosty_home"
    cd "$foundpath" || die "can't cd to $foundpath"
    
    tmpextract="$HOME/ghosty_tmp"
    rm -rf "$tmpextract"
    mkdir -p "$tmpextract" || die "can't create temp dir"
    
    dbg "extracting $zipfile..."
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
    
    # save version from zip, not script
    echo "$zip_version" > "$ghosty_home/.ghosty_version"
    
    if [ $is_upgrade -eq 1 ]; then
        ok "upgraded to v$zip_version"
    else
        ok "installed v$zip_version"
    fi
    
    # restore token
    if [ -n "$old_token" ]; then
        sed -i "s/YOUR_TOKEN_HERE/$old_token/g" "$ghosty_home/config.json" 2>/dev/null
        ok "token restored"
    fi
fi

# run
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

if [ "$token_val" = "YOUR_TOKEN_HERE" ] || [ -z "$token_val" ]; then
    echo ""
    read -p "Enter Discord token: " tok
    [ -z "$tok" ] && die "empty token"
    
    dbg "token length: ${#tok}"
    [[ ! "$tok" =~ ^[A-Za-z0-9._-]+$ ]] && warn "token has weird chars"
    
    dbg "validating with discord..."
    resp=$(curl -s -o /tmp/discord_resp.json -w "%{http_code}" \
        -H "Authorization: $tok" \
        https://discord.com/api/v10/users/@me)
    curl_ret=$?
    
    dbg "curl exit: $curl_ret, http: $resp"
    [ $curl_ret -ne 0 ] && die "curl failed - network issue?"
    
    case "$resp" in
        200)
            ok "token valid"
            cp config.json config.json.bak
            tok_escaped=$(printf '%s\n' "$tok" | sed -e 's/[\/&]/\\&/g')
            sed -i "s/YOUR_TOKEN_HERE/$tok_escaped/g" config.json
            [ $? -ne 0 ] && python3 -c "
import json
with open('config.json','r') as f: c=json.load(f)
c['TOKEN']='$tok'
with open('config.json','w') as f: json.dump(c,f,indent=2)"
            ok "config updated"
            ;;
        401) die "token invalid (401)" ;;
        403) die "token forbidden (403)" ;;
        429) die "rate limited (429)" ;;
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
