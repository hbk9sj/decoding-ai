# Runs Microsoft Presidio (default settings, English) on the fake email and prints what it found.
import time, json, presidio_analyzer, spacy
from presidio_analyzer import AnalyzerEngine
from presidio_anonymizer import AnonymizerEngine
text = open("input_email.txt").read()
t0 = time.perf_counter()
analyzer = AnalyzerEngine()
t1 = time.perf_counter()
results = analyzer.analyze(text=text, language="en")
t2 = time.perf_counter()
out = AnonymizerEngine().anonymize(text=text, analyzer_results=results).text
open("output_redacted.txt", "w").write(out)
print(f"presidio-analyzer {presidio_analyzer.__version__ if hasattr(presidio_analyzer,'__version__') else ''} spacy {spacy.__version__}")
print("recognizers loaded:", sorted({r.name for r in analyzer.get_recognizers('en')}))
print(f"engine load: {t1-t0:.2f} s   analyze: {(t2-t1)*1000:.0f} ms")
for r in sorted(results, key=lambda r: r.start):
    print(f"{r.entity_type:22s} {r.score:.2f}  {text[r.start:r.end]!r}")
