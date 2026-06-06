import requests

try:
    # First get a token for a user that is a taller
    # Or just hit the endpoint without a token, which should return 401 instead of 500
    res = requests.get('http://localhost:8000/api/v1/incidentes/pendientes')
    print("Status:", res.status_code)
    print("Response:", res.text)
except Exception as e:
    print("Error:", e)
