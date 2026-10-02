#!/usr/bin/env python3
"""Compatibility entry point for the former support-only warning generator.

M3 warnings use the same full plural tables and locale kernel as classification.
Check or refresh those tables through the deterministic plural generator.
"""
import sys
from generate_plural_data import main

if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, KeyError) as error:
        print(f"Plural-table generation refused: {error}", file=sys.stderr)
        sys.exit(1)
