#!/usr/bin/env python3
import hashlib, json, re
from pathlib import Path
source = Path(__file__).with_name("panel-ax-hierarchy.txt")
text = source.read_text()
rows = []
for section, actor in [("Attributes", "form"), ("Path to element", "ancestors")]:
    if section == "Attributes":
        lines = [text.splitlines()[0]]
    else:
        lines = text.split("Path to element:\n", 1)[1].split("Query chain:", 1)[0].splitlines()
    for line in lines:
        role = re.search(r"(Application|Window|Group|SplitGroup|ScrollView)\b", line)
        if role:
            rows.append({"actor": actor, "role": role.group(1), "explicitly_disabled": bool(re.search(r", Disabled(?:$|,)", line))})
print(json.dumps({"premise_rejected": "The form is enabled and only its XCTest scroll target is wrong.", "input_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "actor_census": rows, "limit": "AX dump reports disabled ancestors; modifier causality still requires a product change and native rerun."}, indent=2))
