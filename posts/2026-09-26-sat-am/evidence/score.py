# Scores each MarkItDown output against the source table.
# A cell counts as "kept" only if it sits alone in its own markdown table cell,
# on the table row that holds the rest of that record. Also counts characters (tokens not counted: tokenizer download blocked here).
import csv, subprocess, sys
rows = list(csv.reader(open("table.csv")))
data = rows[1:]; total = sum(len(r) for r in data)
files = ["report.pdf", "report.docx", "report.xlsx", "report.pptx", "report_scanned.pdf"]
exe = sys.argv[1]
print(f"source table: {len(data)} data rows x {len(rows[0])} columns = {total} cells\n")
print(f"{'file':<20}{'chars':>7}{'table cols':>12}{'cells kept':>12}{'text present':>14}")
for f in files:
    md = subprocess.run([exe, f], capture_output=True, text=True).stdout
    open(f + ".md", "w").write(md)
    trows = [[c.strip() for c in l.strip().strip("|").split("|")] for l in md.splitlines() if l.strip().startswith("|") and not set(l) <= set("|- ")]
    cols = max((len(r) for r in trows), default=0)
    def row_for(rec):  # the table row whose text contains this record's region name
        return next((t for t in trows if any(c.split(" ")[0] == rec[0] for c in t)), [])
    kept = sum(1 for r in data for v in r if v in row_for(r))
    present = sum(1 for r in data for v in r if v in md)
    print(f"{f:<20}{len(md.strip()):>7}{cols:>12}{f'{kept}/{total}':>12}{f'{present}/{total}':>14}")
