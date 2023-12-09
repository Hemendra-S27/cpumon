from flask import Flask, render_template_string
import psutil

app = Flask(__name__)

@app.route('/')
def home():
    cpu_percentages = psutil.cpu_percent(percpu=True)
    return render_template_string('''
        <ul>
            {% for cpu in cpus %}
                <li>CPU {{ loop.index }}: {{ cpu }}%</li>
            {% endfor %}
        </ul>
    ''', cpus=cpu_percentages)

# Add by local
# Add by Remote
if __name__ == '__main__':
    app.run(host='0.0.0.0')
