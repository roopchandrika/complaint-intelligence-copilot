"""Shared connection settings for the legacy SQL Server (Day 4).

Settings come from the .env file in the project root:
    MSSQL_SA_PASSWORD   admin password (used only by setup_legacy.py)
    LEGACY_RO_PASSWORD  password for the read-only login copilot_readonly
    MSSQL_HOST          default localhost
    MSSQL_PORT          default 1433
    MSSQL_DRIVER        optional, e.g. "ODBC Driver 18 for SQL Server" (auto-detected if empty)
"""
import os

from dotenv import load_dotenv
from sqlalchemy.engine import URL

load_dotenv()

DATABASE = "BankLegacy"
HOST = os.environ.get("MSSQL_HOST", "localhost")
PORT = int(os.environ.get("MSSQL_PORT", "1433"))


def find_driver() -> str:
    """Pick the newest installed 'ODBC Driver NN for SQL Server'."""
    configured = os.environ.get("MSSQL_DRIVER")
    if configured:
        return configured
    import pyodbc

    candidates = [d for d in pyodbc.drivers() if d.startswith("ODBC Driver") and "SQL Server" in d]
    if not candidates:
        raise RuntimeError(
            "No 'ODBC Driver .. for SQL Server' is installed.\n"
            f"Installed ODBC drivers: {pyodbc.drivers()}\n"
            "Install 'Microsoft ODBC Driver 18 for SQL Server' from Microsoft Learn, then try again."
        )
    return sorted(candidates, key=lambda d: int("".join(ch for ch in d if ch.isdigit()) or 0))[-1]


def require(name: str) -> str:
    value = os.environ.get(name)
    if not value:
        raise RuntimeError(f"{name} is not set. Add it to the .env file in the project root.")
    return value


def odbc_conn_str(user: str, password: str, database: str = DATABASE, read_only: bool = False) -> str:
    """Raw ODBC connection string for pyodbc.connect()."""
    pwd = "{" + password.replace("}", "}}") + "}"        # braces protect ; and other special characters
    parts = [
        f"DRIVER={{{find_driver()}}}",
        f"SERVER={HOST},{PORT}",
        f"DATABASE={database}",
        f"UID={user}",
        f"PWD={pwd}",
        "Encrypt=yes",
        "TrustServerCertificate=yes",                     # local self-signed certificate: dev only
    ]
    if read_only:
        parts.append("ApplicationIntent=ReadOnly")
    return ";".join(parts) + ";"


def sqlalchemy_url(user: str, password: str, database: str = DATABASE, read_only: bool = False) -> URL:
    """SQLAlchemy URL. URL.create escapes special characters in the password for us."""
    query = {"driver": find_driver(), "Encrypt": "yes", "TrustServerCertificate": "yes"}
    if read_only:
        query["ApplicationIntent"] = "ReadOnly"
    return URL.create("mssql+pyodbc", username=user, password=password,
                      host=HOST, port=PORT, database=database, query=query)
