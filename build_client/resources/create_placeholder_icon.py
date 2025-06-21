#!/usr/bin/env python3
"""
Create a simple placeholder icon for R2MIDI
"""
try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    print("Please install Pillow: pip install Pillow")
    exit(1)


def create_placeholder_icon():
    # Create a new image with a gradient background
    size = 512
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Draw a rounded rectangle background
    padding = 50
    draw.rounded_rectangle(
        [(padding, padding), (size - padding, size - padding)],
        radius=50,
        fill=(41, 128, 185, 255),  # Nice blue color
        outline=(255, 255, 255, 255),
        width=5,
    )

    # Try to use a nice font, fall back to default if not available
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 120)
    except:
        font = ImageFont.load_default()

    # Draw the text
    text = "R2\nMIDI"
    bbox = draw.textbbox((0, 0), text, font=font)
    text_width = bbox[2] - bbox[0]
    text_height = bbox[3] - bbox[1]

    position = ((size - text_width) // 2, (size - text_height) // 2)
    draw.text(position, text, fill=(255, 255, 255, 255), font=font, align="center")

    # Save the icon
    img.save("r2midi.png", "PNG")
    print("Created placeholder icon: r2midi.png")
    print(
        "This is just a placeholder - please create a proper icon for production use!"
    )


if __name__ == "__main__":
    create_placeholder_icon()
