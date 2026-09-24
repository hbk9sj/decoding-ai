# Builds a fake customer email with planted personal data. Every value is invented.
d=[[0,1,2,3,4,5,6,7,8,9],[1,2,3,4,0,6,7,8,9,5],[2,3,4,0,1,7,8,9,5,6],[3,4,0,1,2,8,9,5,6,7],[4,0,1,2,3,9,5,6,7,8],[5,9,8,7,6,0,4,3,2,1],[6,5,9,8,7,1,0,4,3,2],[7,6,5,9,8,2,1,0,4,3],[8,7,6,5,9,3,2,1,0,4],[9,8,7,6,5,4,3,2,1,0]]
p=[[0,1,2,3,4,5,6,7,8,9],[1,5,7,6,2,8,3,0,9,4],[5,8,0,3,7,9,6,1,4,2],[8,9,1,6,0,4,3,5,2,7],[9,4,5,3,1,2,6,8,7,0],[4,2,8,6,5,7,3,9,0,1],[2,7,9,3,8,0,6,4,1,5],[7,0,4,6,9,1,3,2,5,8]]
inv=[0,4,3,2,1,5,6,7,8,9]
def verhoeff(num):
    c=0
    for i,ch in enumerate(reversed(num+"0")):
        c=d[c][p[i%8][int(ch)]]
    return num+str(inv[c])
aad=verhoeff("48291736504")
aad_fmt=f"{aad[:4]} {aad[4:8]} {aad[8:]}"
text=f"""Hi team,

Please update the KYC file for Priya Raghunathan before Friday.
Her Aadhaar is {aad_fmt} and her PAN is BQRPR4821K.
Date of birth: 14/03/1989.
Mobile: +91 98450 31277. Personal email: priya.r1989@gmail.com.
She pays by UPI to priya.r@okhdfcbank.
Refund the duplicate charge to card 4111 1111 1111 1111.
Bank account 50100234567812, IFSC HDFC0001234.
Address: Flat 4B, Lakeview Apartments, 12th Main Road, Indiranagar, Bengaluru 560038.
Her car, KA05MN4821, is in the office parking.
Passport number: M4827193.
She logged in from 103.21.58.144 last night.

Thanks,
Arjun Mehta
"""
open("input_email.txt","w").write(text)
