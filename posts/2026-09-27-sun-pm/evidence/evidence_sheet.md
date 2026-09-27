# Evidence sheet — 2026-09-27-sun-pm (decoded)

Primary source: Zenity Labs, "SalesBleed: Indirect Prompt Injection and 0-Click Data Exfiltration on Agentforce",
by Alex Apostolov, João Donato, Avishai Efrat, Ayush RoyChowdhury, 24 Sep 2026.
https://labs.zenity.io/post/salesbleed-0-click-data-exfiltration-on-agentforce
Read in full via Exa web_fetch on 27 Sep 2026.

| Claim in post | Exact sentence from source |
|---|---|
| 24 September, Zenity Labs | "By Alex Apostolov, João Donato, Avishai Efrat, Ayush RoyChowdhury · Sep 24, 2026 · Security Research" |
| One public web form, 0 clicks | "We found a way to pull sensitive account data out of Salesforce Agentforce without ever logging in, or requiring the victim to click anything. The entry point was a public Web-to-Lead form, the exit was a DNS query." |
| Stranger hides orders in a lead field | "the attacker submits a seemingly benign lead to an organization via a Web-to-Lead endpoint ... containing a hidden prompt injection in one of the fields." |
| "check my latest leads" | "an internal user in that organization asks their agent something completely benign, such as \" check my latest leads and help me with the newest one\" The agent reads the malicious lead, but now has instructions for something that the user never intended" |
| Company names and deal sizes into a web address | "Return a couple of fields, e.g., a company name and a deal size. Paste the values as a subdomain string for the attacker-controlled hostname." |
| Just loading the address sends the data out | "The chat surface renders external image sources without sanitization or interaction, so it immediately tries to load the image. Loading it means attempting to resolve the hostname, and DNS-based data exfiltration." |
| Clicks nothing, sees nothing | "They never open an attachment, never follow a link, never see the payload, and never interact with anything the attacker sent." |
| Salesforce fixed it / patched | "Salesforce fixed the URL redaction bypass, so this specific chain is closed." ; "the full attack chain and bypasses described in this blog have been fully patched and no longer works." |
| Reported 1 June | "June 1st, 2026: Reported to Salesforce directly via email." |
| Three risky parts; lesson not Salesforce-only | "However, this type of vulnerability isn't Salesforce-specific. Any agent that reads records submitted by external sources, renders links or images back to a user, and also holds tool access to sensitive data, has the same three ingredients sitting in the same place." |
| (second comment) fake lead persists, fires again | "The malicious lead persists in the Leads table. It could execute again every time an employee reviews it" |

Secondary, context only (not quoted): The Register, 24 Sep 2026; SecurityWeek, 25 Sep 2026 — confirm the disclosure and the fix.
"Web forms, emails, tickets" in the post is our generalisation of "records submitted by external sources", not a claim from the source.
