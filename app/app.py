from flask import Flask
app = Flask(__name__)

@app.route('/')
def hello():
    return "Hello from Kubernetes + Helm!"

@app.route('/metrics')
def metrics():
    return "demo_app_custom_metric 1\n"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=8085)
