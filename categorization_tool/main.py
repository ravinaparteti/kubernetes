from flask import Flask

app = Flask(__name__)

@app.route('/')
def home():
    return "Categorization_Tool "

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=9000)
