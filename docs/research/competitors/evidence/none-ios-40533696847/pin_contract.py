def pin_map(value):
    pins = value["pins"]
    result = {pin["identity"]: pin for pin in pins}
    if len(result) != len(pins):
        raise SystemExit("A package graph contains duplicate identities")
    return result

def same_pin(actual, expected):
    return (
        actual["identity"] == expected["identity"]
        and actual["kind"] == expected["kind"]
        and actual["state"] == expected["state"]
        and actual["location"].removesuffix(".git") == expected["location"].removesuffix(".git")
    )

def seed_graph(original_value, reviewed_value):
    original = pin_map(original_value)
    reviewed = pin_map(reviewed_value)
    for name, pin in original.items():
        if name in reviewed and not same_pin(pin, reviewed[name]):
            raise SystemExit("Original and reviewed package pins conflict: " + name)
    seed = dict(original_value)
    seed["pins"] = sorted((reviewed | original).values(), key=lambda pin: pin["identity"])
    return seed

def validate_resolution(resolved_value, original_value, reviewed_value):
    original = pin_map(original_value)
    reviewed = pin_map(reviewed_value)
    resolved = pin_map(resolved_value)
    for name, pin in original.items():
        if name not in resolved or not same_pin(resolved[name], pin):
            raise SystemExit("iOS resolution changed an original pin; package setup remains unverified")
    allowed = reviewed | original
    for name, pin in resolved.items():
        if name not in allowed or not same_pin(pin, allowed[name]):
            raise SystemExit("iOS resolution changed a reviewed package state or repository; package setup remains unverified: " + name)
    return resolved
