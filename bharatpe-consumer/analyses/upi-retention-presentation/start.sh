#!/usr/bin/env bash
cd "$(dirname "$0")"
exec python3 serve.py 2>/dev/null || exec python serve.py
