#!/usr/bin/env python3
"""Reject missing/development backend configuration before a Release build."""
import base64
import os
import re
import sys


def validate(values):
    if values.get('CONFIGURATION') != 'Release':
        return
    host = values.get('MAFIA_PRODUCTION_CONVEX_HOST', '')
    if not re.fullmatch(r'[a-z0-9.-]+\.convex\.cloud', host) or host.startswith('energized-herring-345.'):
        raise ValueError('Set a production Convex host in Configuration/Production.xcconfig.')
    key = values.get('MAFIA_PRODUCTION_CLERK_PUBLISHABLE_KEY', '')
    if not key.startswith('pk_live_'):
        raise ValueError('Set the Clerk production publishable key (pk_live_) in Configuration/Production.xcconfig. Development keys cannot ship.')
    encoded = key[len('pk_live_'):]
    try:
        frontend = base64.b64decode(encoded + '=' * (-len(encoded) % 4), validate=True).decode()
    except (ValueError, UnicodeError):
        raise ValueError('The Clerk production publishable key is invalid.') from None
    if not frontend.endswith('$'):
        raise ValueError('The Clerk production publishable key is invalid.')
    frontend = frontend[:-1]
    if not re.fullmatch(r'[a-z0-9.-]+\.[a-z]+', frontend) or frontend.endswith('.accounts.dev'):
        raise ValueError('The Clerk production key must reference a production frontend domain.')
    if values.get('MAFIA_CLERK_FRONTEND_HOST') != frontend:
        raise ValueError('Set MAFIA_CLERK_FRONTEND_HOST to the production domain for this Clerk key, so associated domains match.')


if __name__ == '__main__':
    try:
        validate(os.environ)
    except ValueError as error:
        print(f'error: {error}', file=sys.stderr)
        sys.exit(1)
