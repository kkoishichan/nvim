import sys


def answer() -> int:  # DEFINITION_TARGET
    return 42


value = answer()  # DEFINITION
print(value, sys.prefix)  # BREAKPOINT
