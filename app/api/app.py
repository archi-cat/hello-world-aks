import os
import struct
import pyodbc
from flask import Flask, jsonify
from azure.identity import ManagedIdentityCredential

app = Flask(__name__)


def get_db_connection():
    """
    Connect to Azure SQL Database using Managed Identity.
    No username or password — Azure issues a short-lived token instead.
    """
    server   = os.environ["SQL_SERVER"]    # e.g. sql-hello-world.database.windows.net
    database = os.environ["SQL_DATABASE"]  # e.g. sqldb-hello-world

    # Step 1 — get a bearer token from Azure using the app's Managed Identity
    credential = ManagedIdentityCredential()
    token = credential.get_token("https://database.windows.net/.default")

    # Step 2 — pack the token into the format pyodbc expects
    token_bytes = token.token.encode("utf-16-le")
    token_struct = struct.pack(f"<I{len(token_bytes)}s", len(token_bytes), token_bytes)

    # Step 3 — connect using the token (SQL_COPT_SS_ACCESS_TOKEN = 1256)
    connection_string = (
        f"DRIVER={{ODBC Driver 18 for SQL Server}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"Encrypt=yes;"
        f"TrustServerCertificate=no;"
    )
    conn = pyodbc.connect(connection_string, attrs_before={1256: token_struct})
    return conn


@app.route("/health")
def health():
    return "OK", 200


@app.route("/db-check")
def db_check():
    """
    Attempt a lightweight query against the database.
    Returns a JSON response the web app will display.
    """
    try:
        conn   = get_db_connection()
        cursor = conn.cursor()

        # SELECT @@VERSION returns the SQL Server version string —
        # a reliable way to confirm the connection is live
        cursor.execute("SELECT @@VERSION")
        row     = cursor.fetchone()
        version = row[0] if row else "unknown"

        cursor.close()
        conn.close()

        return jsonify({
            "status":  "ok",
            "message": "Database connection successful",
            "db_version": version
        }), 200

    except Exception as e:
        return jsonify({
            "status":  "error",
            "message": "Database connection failed",
            "detail":  str(e)
        }), 500
# ```

# **How Managed Identity auth works here:**

# - When the API runs inside Azure App Service, it has an identity assigned to it by Azure AD
# - `ManagedIdentityCredential()` calls the Azure Instance Metadata Service (a local endpoint only reachable from inside Azure) to get a short-lived token
# - That token is packed into a binary struct that pyodbc knows how to pass to the ODBC driver
# - The SQL database trusts tokens signed by Azure AD — no password is ever stored or transmitted
# - Outside of Azure (local dev) this will fail — see the note below on local testing

# > For local development, you can temporarily swap `ManagedIdentityCredential()` for `DefaultAzureCredential()` and run `az login` — it will use your personal Azure CLI credentials instead. Never commit this change.

# ---
