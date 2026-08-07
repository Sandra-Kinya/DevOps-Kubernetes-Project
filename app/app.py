from flask import Flask, Response
import  os

app = Flask(__name__)

GREETING = os.environ.get("APP_GREETING", "Hello from Kubernetes + Helm!")
request_count = 0

@app.route('/')
def hello():
    global request_count
    request_count += 1
    return GREETING

@app.route('/metrics')
def metrics():
    return Response(f"demo_app_custom_metric {request_count}\n", mimetype="text/plain")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8085)
