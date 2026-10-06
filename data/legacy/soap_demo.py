"""Day 4 (optional): call a SOAP web service with Zeep and turn the XML answer into JSON.

Run:  pip install zeep
      python data/legacy/soap_demo.py
      python data/legacy/soap_demo.py https://some.other/service?WSDL     # any public WSDL

Public demo services go offline from time to time. If the default one fails, try another WSDL URL;
the skill being practised is: read a WSDL, call an operation, convert the result to JSON.
"""
import json
import sys

from zeep import Client
from zeep.helpers import serialize_object

WSDL = sys.argv[1] if len(sys.argv) > 1 else "http://www.dneonline.com/calculator.asmx?WSDL"

try:
    client = Client(WSDL)
except Exception as e:
    sys.exit(f"Could not load the WSDL ({type(e).__name__}: {e}).\nThe demo service may be down; try another WSDL URL.")

# 1. Read the contract: which operations exist and what they take
print(f"WSDL: {WSDL}\nOperations:")
for service in client.wsdl.services.values():
    for port in service.ports.values():
        for name, operation in port.binding._operations.items():
            print(f"  {name}{operation.input.signature()}")
        break   # one port is enough to see the operations

# 2. Call operations (only for the default calculator service)
if "dneonline" in WSDL:
    added = client.service.Add(intA=2, intB=3)
    multiplied = client.service.Multiply(intA=6, intB=7)
    result = {"Add(2,3)": serialize_object(added), "Multiply(6,7)": serialize_object(multiplied)}
    print("\nResults as JSON:")
    print(json.dumps(result, indent=2))

# 3. See the raw XML envelope Zeep would send (what travels over the wire)
if "dneonline" in WSDL:
    envelope = client.create_message(client.service, "Add", intA=2, intB=3)
    from lxml import etree
    print("\nSOAP request envelope:")
    print(etree.tostring(envelope, pretty_print=True).decode())
