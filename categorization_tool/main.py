from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Hello, Kubernetes! Hi, From Kunal!!! Deploy using CICD"

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9000)
