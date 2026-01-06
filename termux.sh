#!/data/data/com.termux/files/usr/bin/bash
# Made by Bisam - DEBUG VERSION

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

exec > >(tee -a ~/ghosty_crash.log) 2>&1
echo "=== RUN $(date) ===" >> ~/ghosty_crash.log

clear
echo "=== GhoSty OwO Auto Setup ==="
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
dbg "ghosty_home = $ghosty_home"

if [ -d "$ghosty_home" ] && [ -f "$ghosty_home/config.json" ]; then
    dbg "existing install found"
    cd "$ghosty_home" || die "can't cd to $ghosty_home"
    
    dbg "config preview:"
    cat config.json | sed 's/"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"/"TOKEN": "***"/g' | head -15
    
    token_val=$(grep -o '"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' config.json | cut -d'"' -f4)
    dbg "token: ${token_val:0:10}..."
    
    if [ "$token_val" = "YOUR_TOKEN_HERE" ] || [ -z "$token_val" ]; then
        echo ""
        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
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
        [ -f /tmp/discord_resp.json ] && dbg "response: $(cat /tmp/discord_resp.json | head -3)"
        
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
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    dbg "python: $(python --version 2>&1)"
    dbg "pwd: $(pwd)"
    [ ! -f "main.py" ] && die "main.py not found"
    dbg "main.py: yes"
    
    echo "starting bot..."
    sleep 1
    python main.py
    py_ret=$?
    [ $py_ret -ne 0 ] && die "python exited with code $py_ret"
    exit
fi
# fresh install
dbg "starting fresh install..."

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

dbg "searching for zip..."
for p in "${paths[@]}"; do
    [ ! -d "$p" ] && continue
    dbg "checking: $p"
    for zf in "$p"/GhoSty*OwO*.zip "$p"/ghosty*.zip "$p"/Ghosty*.zip; do
        if [ -f "$zf" ]; then
            zipfile=$(basename "$zf")
            foundpath="$p"
            ok "found: $zf"
            break 2
        fi
    done
done

if [ -z "$foundpath" ]; then
    warn "ZIP NOT FOUND"
    echo "searched:"
    for p in "${paths[@]}"; do
        [ -d "$p" ] && echo "  [yes] $p" || echo "  [no]  $p"
    done
    die "download GhoSty zip to Downloads"
fi

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

[ $count -eq 1 ] && [ -d "$tmpextract/$first" ] && mv "$tmpextract/$first" "$ghosty_home" || mv "$tmpextract" "$ghosty_home"
rm -rf "$tmpextract"

cd "$ghosty_home" || die "can't cd ghosty_home"
dbg "contents:"; ls -la | head -8
[ ! -f "config.json" ] && die "config.json missing"
ok "installed to $ghosty_home"

token_val=$(grep -o '"TOKEN"[[:space:]]*:[[:space:]]*"[^"]*"' config.json | cut -d'"' -f4)
if [ "$token_val" = "YOUR_TOKEN_HERE" ] || [ -z "$token_val" ]; then
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    read -p "Enter Discord token: " tok
    [ -z "$tok" ] && die "empty token"
    
    resp=$(curl -s -o /tmp/discord_resp.json -w "%{http_code}" -H "Authorization: $tok" https://discord.com/api/v10/users/@me)
    dbg "http: $resp"
    
    [ "$resp" = "200" ] && { ok "valid"; sed -i "s/YOUR_TOKEN_HERE/$tok/g" config.json; ok "updated"; } || die "invalid token ($resp)"
fi

dbg "installing deps..."
pkg update -y 2>&1 | tail -2
for p in python python-pillow python-numpy; do
    dpkg -s $p &>/dev/null || pkg install -y $p 2>&1 | tail -3
done
command -v pip &>/dev/null || pkg install -y python-pip
[ -f "requirements.txt" ] && pip install -r requirements.txt 2>&1 | tail -8

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ok "setup complete"
dbg "python: $(python --version 2>&1)"
[ ! -f "main.py" ] && die "main.py missing"

echo "starting bot..."
sleep 1
python main.py
[ $? -ne 0 ] && die "bot crashed"
