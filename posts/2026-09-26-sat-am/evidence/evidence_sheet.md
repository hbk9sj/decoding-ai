# Evidence sheet — 2026-09-26 sat-am (tried: MarkItDown)

## Primary source
- Publisher: Microsoft, microsoft/markitdown README on GitHub (accessed 26 Sep 2026)
- URL: https://github.com/microsoft/markitdown
- Exact sentence: "MarkItDown is a lightweight Python utility for converting various files to Markdown for use with LLMs and related text analysis pipelines. To this end, it is most comparable to textract, but with a focus on preserving important document structure and content as Markdown (including: headings, lists, tables, links, etc.)"
- Exact sentence: "Plugins are disabled by default."
- Related: packages/markitdown-ocr/README.md (same repo): "LLM Vision plugin for MarkItDown that extracts text from images embedded in PDF, DOCX, PPTX, and XLSX files." and "If no `llm_client` is provided the plugin still loads, but OCR is silently skipped — falling back to the standard built-in converter."

## Measured in this session (markitdown 0.1.8, see versions.txt)
- One table: 6 data rows x 5 columns = 30 cells (table.csv, make_input.py)
- Word, Excel, PowerPoint: 30/30 cells in their own cell on the right row (scoring.txt)
- PDF (text PDF from reportlab): table came out with 3 columns instead of 5; 6/30 cells in their own cell (the Q2 column); all 30 values still present as text (scoring.txt, output_report_pdf.md)
- Word: header row came out as a data row under an empty header (output_report_docx.md)
- Scanned PDF (table drawn as an image): 0 characters, exit code 0, no warning (markitdown_run.txt)
- Not measured: token counts (tokenizer download blocked by this sandbox's proxy); real-world PDFs; the OCR plugin (needs an LLM client)
