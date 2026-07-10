#!/bin/bash
# Builds dist/Auricle-<version>.dmg: classic drag-to-Applications disk image with a
# rendered background that carries the first-launch Gatekeeper instructions.
# Expects dist/Auricle.app to exist (run scripts/build-app.sh first).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_NAME="Auricle"
VERSION="$(cat "$ROOT/VERSION" 2>/dev/null || echo 0.0.0)"
APP="$ROOT/dist/$APP_NAME.app"
DMG="$ROOT/dist/$APP_NAME-$VERSION.dmg"
STAGE="$(mktemp -d)/dmg"
VOLNAME="$APP_NAME $VERSION"

[ -d "$APP" ] || { echo "error: $APP missing — run scripts/build-app.sh first" >&2; exit 1; }

mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

python3 - "$STAGE/.background/bg.png" <<'PY'
import sys
from PIL import Image, ImageDraw, ImageFilter, ImageFont

W, H = 1200, 800  # 600x400 pt at 2x (dpi 144)
img = Image.new("RGB", (W, H), "#1E2430")
top, bottom = (30, 36, 48), (12, 15, 22)
for y in range(H):
    t = y / H
    img.paste(tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)), (0, y, W, y + 1))

draw = ImageDraw.Draw(img)

def font(size, bold=False):
    for name in (["/System/Library/Fonts/SFNSDisplay-Bold.otf" if bold else "/System/Library/Fonts/SFNSDisplay.otf",
                  "/System/Library/Fonts/HelveticaNeue.ttc"]):
        try:
            return ImageFont.truetype(name, size, index=1 if (bold and name.endswith(".ttc")) else 0)
        except OSError:
            continue
    return ImageFont.load_default()

# soft glow accents echoing the app icon palette
glow = Image.new("RGB", (W, H), (0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.ellipse((200, 250, 500, 500), fill=(20, 34, 46))
gd.ellipse((760, 250, 1060, 500), fill=(26, 22, 46))
glow = glow.filter(ImageFilter.GaussianBlur(90))
img = Image.blend(img, Image.blend(img, glow, 0.5), 0.6)
draw = ImageDraw.Draw(img)

# arrow between the two icon slots (icons sit at pt (150,175) and (450,175) -> px (300,350)/(900,350))
ay, x0, x1 = 350, 430, 740
draw.line((x0, ay, x1 - 36, ay), fill=(122, 92, 255), width=10)
draw.polygon([(x1, ay), (x1 - 52, ay - 30), (x1 - 52, ay + 30)], fill=(122, 92, 255))
draw.line((x0, ay, x1 - 36, ay), fill=(90, 200, 250), width=4)

def center(text, y, f, color):
    w = draw.textlength(text, font=f)
    draw.text(((W - w) / 2, y), text, font=f, fill=color)

center("Auricle'ı Applications klasörüne sürükleyin", 540, font(34, bold=True), (235, 238, 245))
center("Drag Auricle into the Applications folder", 592, font(24), (150, 158, 175))
line1 = "İlk açılışta macOS uygulamayı engelleyebilir:  Sistem Ayarları › Gizlilik ve Güvenlik › “Yine de Aç”"
line2 = "If macOS blocks the first launch:  System Settings › Privacy & Security › “Open Anyway”"
center(line1, 676, font(21), (122, 150, 250))
center(line2, 712, font(19), (110, 120, 140))

img.save(sys.argv[1], dpi=(144, 144))
print("background rendered")
PY

rm -f "$DMG"
RW="$(mktemp -d)/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOLNAME" -fs HFS+ -format UDRW -size 80m "$RW" -quiet
MOUNT="$(hdiutil attach "$RW" -readwrite -noverify -noautoopen | awk -F'\t' '/\/Volumes\//{print $NF}')"

# Finder layout: icon view, background, positions. Best-effort — a permission denial
# still leaves a fully functional (just unstyled) image.
if osascript <<EOF
tell application "Finder"
  tell disk "$VOLNAME"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 140, 800, 596}
    set viewOptions to the icon view options of container window
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 104
    set text size of viewOptions to 13
    set background picture of viewOptions to file ".background:bg.png"
    set position of item "$APP_NAME.app" of container window to {150, 175}
    set position of item "Applications" of container window to {450, 175}
    close
    open
    delay 1
    close
  end tell
end tell
EOF
then echo "finder layout applied"; else echo "warning: finder layout skipped" >&2; fi

sync
hdiutil detach "$MOUNT" -quiet
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG" -quiet
rm -f "$RW"
echo "created: $DMG"
