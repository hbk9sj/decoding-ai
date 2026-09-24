# Same email, same engine, plus the six India recognizers Presidio ships switched off.
import time
from presidio_analyzer import AnalyzerEngine
from presidio_analyzer.predefined_recognizers import (InAadhaarRecognizer, InPanRecognizer,
    InPassportRecognizer, InVehicleRegistrationRecognizer, InVoterRecognizer, InGstinRecognizer)
from presidio_anonymizer import AnonymizerEngine
text = open("input_email.txt").read()
analyzer = AnalyzerEngine()
for R in (InAadhaarRecognizer, InPanRecognizer, InPassportRecognizer,
          InVehicleRegistrationRecognizer, InVoterRecognizer, InGstinRecognizer):
    analyzer.registry.add_recognizer(R())
t = time.perf_counter()
results = analyzer.analyze(text=text, language="en")
print(f"analyze: {(time.perf_counter()-t)*1000:.0f} ms")
for r in sorted(results, key=lambda r: r.start):
    print(f"{r.entity_type:24s} {r.score:.2f}  {text[r.start:r.end]!r}")
out = AnonymizerEngine().anonymize(text=text, analyzer_results=results).text
open("output_redacted_india.txt", "w").write(out)
