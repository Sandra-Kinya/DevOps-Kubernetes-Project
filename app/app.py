from flask import Flask, Response
import  os

app = Flask(__name__)

GREETING = os.environ.get("APP_GREETING", "Hello from Kubernetes + Helm!")

@app.route('/')
def hello():
    return GREETING

@app.route('/metrics')
def metrics():
    return Response("demo_app_custom_metric 1\n", mimetype="text/plain")

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8085)
