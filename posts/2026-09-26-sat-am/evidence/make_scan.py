# Makes a "scanned" copy: the same table drawn as a picture and saved as a one-page PDF.
import csv
from PIL import Image, ImageDraw, ImageFont
rows = list(csv.reader(open("table.csv")))
img = Image.new("RGB", (1240, 700), "white"); d = ImageDraw.Draw(img)
try: font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", 26)
except Exception: font = ImageFont.load_default()
d.text((60, 40), "Regional sales, Q1 vs Q2 2026 (INR thousands)", fill="black", font=font)
for i, r in enumerate(rows):
    for j, v in enumerate(r): d.text((60 + j*230, 120 + i*60), v, fill="black", font=font)
img.save("report_scanned.pdf", "PDF", resolution=150)
print("built report_scanned.pdf")
