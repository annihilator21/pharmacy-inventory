"""Shared database connection helper for the AI scripts.

Reads DB_HOST, DB_PORT, DB_NAME, DB_USER and DB_PASSWORD from the environment
or from a .env file in the repo root (copy .env.example to .env and edit it).
Never commit the .env file.
"""
import os
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

REPO_ROOT = Path(__file__).resolve().parent.parent
load_dotenv(REPO_ROOT / ".env")


def get_connection():
    """Open a new connection to the pharmacy database."""
    return psycopg2.connect(
        host=os.getenv("DB_HOST", "localhost"),
        port=os.getenv("DB_PORT", "5432"),
        dbname=os.getenv("DB_NAME", "pharmacy"),
        user=os.getenv("DB_USER", "postgres"),
        password=os.getenv("DB_PASSWORD", ""),
    )
