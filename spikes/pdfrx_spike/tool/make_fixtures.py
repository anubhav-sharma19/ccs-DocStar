"""Generate FAKE test PDFs (synthetic values only) + ground truth for the pdfrx spike.

Run:  python tool/make_fixtures.py   (needs reportlab, pypdf, cryptography)
Outputs to assets/fixtures/. rupee_1p.pdf embeds a subset of STIX Two Text (SIL OFL, safe to commit).
"""
import json, pathlib, random
from reportlab.pdfgen import canvas
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from pypdf import PdfReader, PdfWriter
import reportlab, os

OUT = pathlib.Path(__file__).resolve().parent.parent / "assets" / "fixtures"
OUT.mkdir(parents=True, exist_ok=True)
W, H = 595.0, 842.0
VERA = os.path.join(os.path.dirname(reportlab.__file__), "fonts", "Vera.ttf")
pdfmetrics.registerFont(TTFont("Vera", VERA))
RUPEE_FONT = "/System/Library/Fonts/Supplemental/STIXTwoText.ttf"  # OFL; has U+20B9
PASSWORD = "Test1234"  # fake, fixture only

# Probes sit in different quadrants so an axis swap or flip is unmistakable.
PROBES = [("PROBE-ALPHA", 60, 700, 14), ("PROBE-BETA", 300, 300, 14), ("PROBE-GAMMA", 470, 100, 10)]


def lakh(n: int) -> str:
    s = f"{n:d}"
    if len(s) <= 3:
        return s
    head, tail = s[:-3], s[-3:]
    parts = []
    while len(head) > 2:
        parts.insert(0, head[-2:])
        head = head[:-2]
    if head:
        parts.insert(0, head)
    return ",".join(parts + [tail])


def draw_page(c, page, rng, font="Vera", rows=45, probes=True):
    c.setFont(font, 9)
    c.drawString(40, 815, f"FAKE BANK STATEMENT - SYNTHETIC TEST DATA - PAGE {page + 1}")
    for x, label in [(40, "DATE"), (110, "DESCRIPTION"), (330, "DEBIT"), (400, "CREDIT"), (480, "BALANCE")]:
        c.drawString(x, 795, label)
    bal = 500000
    y = 780
    for i in range(rows):
        amt = rng.randint(100, 99999)
        debit = rng.random() < 0.6
        bal += -amt if debit else amt
        c.drawString(40, y, f"{(i % 28) + 1:02d}/{(page % 12) + 1:02d}/2026")
        c.drawString(110, y, f"FAKE MERCHANT {rng.randint(1000, 9999)} REF{rng.randint(10**8, 10**9 - 1)}")
        c.drawString(330 if debit else 400, y, f"{lakh(amt)}.{rng.randint(0, 99):02d}")
        c.drawString(480, y, f"{lakh(bal)}.{rng.randint(0, 99):02d}")
        y -= 15
    if probes:
        for text, px, py, size in PROBES:
            c.setFont(font, size)
            c.drawString(px, py, text)
            c.setFont(font, 9)


def make(name, pages=1, rotate=0, crop=None, font="Vera", extra=None, seed=7):
    rng = random.Random(seed)
    path = OUT / name
    c = canvas.Canvas(str(path), pagesize=(W, H), pageCompression=0)
    for p in range(pages):
        draw_page(c, p, rng, font=font)
        if extra:
            extra(c)
        if rotate:
            c.setPageRotation(rotate)
        if crop:
            c.setCropBox(crop)
        c.showPage()
    c.save()
    return {
        "file": name, "pages": pages, "rotation": rotate, "mediabox": [0, 0, W, H],
        "cropbox": crop, "password": None,
        "probes": [{"text": t, "x": x, "y": y, "size": s,
                    "width": pdfmetrics.stringWidth(t, font, s)} for t, x, y, s in PROBES],
    }


def rupee_extra(c):
    # Amount-adjacent symbols. Unicode rupee needs a TTF that has the glyph.
    c.setFont("ArialU", 10)
    c.drawString(40, 140, "₹ 1,23,456.78")
    c.setFont("Vera", 10)
    c.drawString(200, 140, "` 2,500.00")
    c.drawString(340, 140, "C 99.00")


manifest = []
manifest.append(make("plain_1p.pdf"))
for r in (90, 180, 270):
    m = make(f"rot{r}_1p.pdf")  # unrotated content; /Rotate added below without touching MediaBox
    rd = PdfReader(str(OUT / m["file"]))
    wr = PdfWriter()
    for pg in rd.pages:
        pg.rotate(r)
        wr.add_page(pg)
    with open(OUT / m["file"], "wb") as f:
        wr.write(f)
    m["rotation"] = r
    manifest.append(m)
manifest.append(make("cropbox_1p.pdf", crop=(50, 60, 545, 782)))
manifest.append(make("ten_pages.pdf", pages=10))

# locked copy of the plain page (AES-256)
reader = PdfReader(str(OUT / "plain_1p.pdf"))
writer = PdfWriter()
for pg in reader.pages:
    writer.add_page(pg)
writer.encrypt(PASSWORD, algorithm="AES-256")
with open(OUT / "locked_1p.pdf", "wb") as f:
    writer.write(f)
m = dict(manifest[0]); m.update(file="locked_1p.pdf", password=PASSWORD)
manifest.append(m)

if pathlib.Path(RUPEE_FONT).exists():
    pdfmetrics.registerFont(TTFont("ArialU", RUPEE_FONT))
    manifest.append(make("rupee_1p.pdf", extra=rupee_extra))

(OUT / "manifest.json").write_text(json.dumps(manifest, indent=1))
print("wrote", len(manifest), "fixtures to", OUT)
