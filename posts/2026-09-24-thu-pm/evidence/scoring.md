# Scoring — what Presidio hid in one fake KYC email (all data invented)

Presidio 2.2.364, spaCy 3.8.16, en_core_web_lg 3.8.0, run 24 Sep 2026 in this session.
14 planted personal items. IFSC (a public branch code) not counted.

| # | Item | Default run | India recognizers switched on |
|---|---|---|---|
| 1 | Name: Priya Raghunathan | hidden (PERSON) | hidden (PERSON) |
| 2 | Name: Arjun Mehta | hidden (PERSON) | hidden (PERSON) |
| 3 | Aadhaar 4829 1736 5048 | hidden, WRONG label (DATE_TIME) | hidden (IN_AADHAAR) |
| 4 | PAN BQRPR4821K | LEAKED in full | hidden (IN_PAN) |
| 5 | Date of birth 14/03/1989 | hidden (DATE_TIME) | hidden (DATE_TIME) |
| 6 | Mobile +91 98450 31277 | hidden (PHONE_NUMBER) | hidden (PHONE_NUMBER) |
| 7 | Email priya.r1989@gmail.com | hidden (EMAIL_ADDRESS) | hidden (EMAIL_ADDRESS) |
| 8 | UPI ID priya.r@okhdfcbank | LEAKED in full | PARTLY: "priya.r@" left, bank part tagged IN_PAN at score 0.01 |
| 9 | Card 4111 1111 1111 1111 | hidden (CREDIT_CARD) | hidden (CREDIT_CARD) |
| 10 | Bank account 50100234567812 | hidden (US_BANK_NUMBER) | hidden (US_BANK_NUMBER) |
| 11 | Address Flat 4B ... 560038 | PARTLY: "Flat 4B" and "12th Main Road" left | PARTLY: same |
| 12 | Car plate KA05MN4821 | hidden, WRONG label (PERSON) | hidden (IN_VEHICLE_REGISTRATION) |
| 13 | Passport M4827193 | hidden, WRONG label (US_DRIVER_LICENSE) | hidden (IN_PASSPORT) |
| 14 | IP 103.21.58.144 | hidden, WRONG label (DATE_TIME, with the words "last night") | same |

Default run: 11 of 14 hidden, 2 leaked in full (PAN, UPI ID), 1 partly (address).
  4 of the 11 were hidden under the wrong label (Aadhaar, car plate, passport, IP).
India recognizers on: 12 of 14 hidden, 0 leaked in full, 2 partly (UPI ID, address).

Why: the six India recognizers ship in the package with `enabled: false`
(see default_recognizers_india_excerpt.yaml; the default run's recognizer list has none of them).
