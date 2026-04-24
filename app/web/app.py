import os
import requests
from flask import Flask, render_template_string

app = Flask(__name__)

# The API URL is injected via an environment variable set in Terraform
# e.g. https://api-hello-world-yourname.azurewebsites.net
API_URL = os.environ.get("API_URL", "http://localhost:8001")

HTML_TEMPLATE = """
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Hello World</title>
    <style>
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
            max-width: 640px;
            margin: 80px auto;
            padding: 0 24px;
            color: #1a1a1a;
        }
        h1 { font-size: 2rem; font-weight: 600; margin-bottom: 8px; }
        .card {
            margin-top: 32px;
            border: 1px solid #e5e5e5;
            border-radius: 8px;
            padding: 24px;
        }
        .card h2 { font-size: 1rem; font-weight: 600; margin: 0 0 16px; }
        .status {
            display: inline-block;
            padding: 4px 10px;
            border-radius: 4px;
            font-size: 0.875rem;
            font-weight: 500;
        }
        .status.ok      { background: #dcfce7; color: #166534; }
        .status.error   { background: #fee2e2; color: #991b1b; }
        .status.unknown { background: #f3f4f6; color: #374151; }
        .detail {
            margin-top: 12px;
            font-size: 0.875rem;
            color: #6b7280;
            word-break: break-word;
        }
        .version {
            margin-top: 8px;
            font-size: 0.8rem;
            color: #9ca3af;
            font-family: monospace;
        }
    </style>
</head>
<body>
    <h1>Hello World!</h1>
    <p>A two-tier Python application running on AKS.</p>

    <div class="card">
        <h2>Database connectivity check</h2>

        {% if db_status == "ok" %}
            <span class="status ok">Connected</span>
            <p class="detail">{{ db_message }}</p>
            <p class="version">{{ db_version }}</p>
        {% elif db_status == "error" %}
            <span class="status error">Connection failed</span>
            <p class="detail">{{ db_message }}</p>
            <p class="detail">{{ db_detail }}</p>
        {% else %}
            <span class="status unknown">API unreachable</span>
            <p class="detail">{{ db_message }}</p>
        {% endif %}
    </div>
</body>
</html>
"""


@app.route("/health")
def health():
    return "OK", 200


@app.route("/")
def index():
    """
    Call the API's /db-check endpoint and render the result.
    Handles three states: success, API returned an error, API unreachable.
    """
    try:
        response = requests.get(f"{API_URL}/db-check", timeout=10)
        data = response.json()

        return render_template_string(
            HTML_TEMPLATE,
            db_status  = data.get("status", "unknown"),
            db_message = data.get("message", ""),
            db_detail  = data.get("detail", ""),
            db_version = data.get("db_version", "")
        )

    except requests.exceptions.RequestException as e:
        return render_template_string(
            HTML_TEMPLATE,
            db_status  = "unknown",
            db_message = f"Could not reach API at {API_URL}",
            db_detail  = str(e),
            db_version = ""
        )