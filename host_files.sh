#!/usr/bin/env bash
# Uploads every F-15 file in this folder to catbox, checks that each link really serves the
# whole file (catbox sometimes stores empty files), then writes the links into the chip's
# LINKS block. Run from Git Bash:   bash host_files.sh
cd "$(dirname "$0")" || exit 1
CHIP="E:/SteamLibrary/steamapps/common/GarrysMod/garrysmod/data/starfall/f15/f15.txt"
API="https://catbox.moe/user/api.php"

upload() {   # file -> prints a verified link, or nothing
    local f="$1" size u got try
    size=$(stat -c %s "$f")
    for try in 1 2 3; do
        u=$(curl -s --max-time 180 -F "reqtype=fileupload" -F "fileToUpload=@$f" "$API")
        case "$u" in https://files.catbox.moe/*) ;; *) sleep 5; continue ;; esac
        sleep 2
        got=$(curl -s --max-time 120 -o /dev/null -w '%{size_download}' "$u")
        if [ "$got" = "$size" ]; then echo "$u"; return 0; fi
        echo "  $f: catbox serves $got of $size bytes, retrying" >&2
        sleep 8
    done
    return 1
}

# quick health check with the smallest file so a broken catbox fails fast
probe=$(ls -S sounds/*.ogg | tail -1)
if ! upload "$probe" > /dev/null; then
    echo "Catbox is storing empty files right now - nothing changed. Try again later,"
    echo "or put this folder on GitHub and set FILE_BASE in the chip instead."
    exit 1
fi

: > catbox_links.new
for f in f15.obj f15_albedo.jpg f15_normal.png sounds/*.ogg; do
    url=$(upload "$f") || { echo "FAILED: $f - chip not changed"; rm -f catbox_links.new; exit 1; }
    echo "$f $url" | tee -a catbox_links.new
done
mv catbox_links.new catbox_links.txt

python - "$CHIP" catbox_links.txt <<'PYEOF'
import sys
chip, links = sys.argv[1], sys.argv[2]
src = open(chip, encoding="utf-8", newline="").read()
a = src.index("-- LINKS BEGIN")
b = src.index("-- LINKS END")
line_start = src.rfind("\n", 0, a) + 1
indent = src[line_start:a]
rows = [l.split() for l in open(links, encoding="utf-8") if l.strip()]
body = "-- LINKS BEGIN\n" + "".join('%s["%s"] = "%s",\n' % (indent, n, u) for n, u in rows) + indent
src = src[:a] + body + src[b:]
open(chip, "w", encoding="utf-8", newline="\n").write(src)
print("wrote %d links into %s" % (len(rows), chip))
PYEOF
