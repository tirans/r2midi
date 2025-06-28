# Icon Requirements for R2MIDI

You need to create the following icon files:

## 1. Base Icon (PNG)
- **File**: `r2midi.png`
- **Size**: 512x512 pixels minimum (1024x1024 recommended)
- **Format**: PNG with transparency

## 2. Windows Icon
- **File**: `r2midi.ico`
- **Sizes**: Should contain multiple resolutions:
  - 16x16
  - 32x32
  - 48x48
  - 256x256
- **Tool**: Use ImageMagick or online converter

## 3. macOS Icon
- **File**: `r2midi.icns`
- **Sizes**: Should contain:
  - 16x16
  - 32x32
  - 128x128
  - 256x256
  - 512x512
  - 1024x1024
- **Tool**: Use `iconutil` on macOS or `png2icns`

## Creating Icons with ImageMagick

If you have ImageMagick installed:

```bash
# Create Windows .ico from PNG
convert r2midi.png -define icon:auto-resize=256,128,96,64,48,32,16 r2midi.ico

# For macOS, first create the iconset
mkdir r2midi.iconset
sips -z 16 16     r2midi.png --out r2midi.iconset/icon_16x16.png
sips -z 32 32     r2midi.png --out r2midi.iconset/icon_16x16@2x.png
sips -z 32 32     r2midi.png --out r2midi.iconset/icon_32x32.png
sips -z 64 64     r2midi.png --out r2midi.iconset/icon_32x32@2x.png
sips -z 128 128   r2midi.png --out r2midi.iconset/icon_128x128.png
sips -z 256 256   r2midi.png --out r2midi.iconset/icon_128x128@2x.png
sips -z 256 256   r2midi.png --out r2midi.iconset/icon_256x256.png
sips -z 512 512   r2midi.png --out r2midi.iconset/icon_256x256@2x.png
sips -z 512 512   r2midi.png --out r2midi.iconset/icon_512x512.png
sips -z 1024 1024 r2midi.png --out r2midi.iconset/icon_512x512@2x.png

# Then convert to .icns
iconutil -c icns r2midi.iconset
```

## Placeholder Icon

For testing, you can use a simple colored square or download a free MIDI-related icon from:
- https://www.flaticon.com/
- https://icons8.com/
- https://www.iconfinder.com/

Make sure any icon you use is properly licensed for your use case.
