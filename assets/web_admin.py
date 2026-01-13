from flask import Flask, request, render_template_string
import json
import subprocess
import os

app = Flask(__name__)
CONFIG_FILE = "/boot/halo.json"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
  body { font-family: sans-serif; background: #222; color: #fff; padding: 20px; }
  input, select { width: 100%; padding: 10px; margin: 10px 0; background: #333; color: #fff; border: 1px solid #555; }
  button { width: 100%; padding: 15px; background: #007bff; color: white; border: none; font-size: 18px; margin-top: 20px; }
  .warning { color: #ffcc00; font-size: 12px; margin-bottom: 20px; display: block;}
</style>
</head>
<body>
<h2>Halo Admin</h2>
<form method="POST">
  <label>Mesh ID (Password)</label>
  <input type="text" name="mesh_id" value="{{ conf.mesh_id }}">
  
  <label>Frequency (MHz)</label>
  <input type="number" name="freq" value="{{ conf.freq }}">
  
  <label>Internet Gateway Mode</label>
  <div class="warning">AUTO enables Internet Sharing when Ethernet/USB is detected.</div>
  <select name="gateway">
    <option value="auto" {% if conf.gateway == 'auto' %}selected{% endif %}>AUTO (Hot-Swap)</option>
    <option value="off" {% if conf.gateway == 'off' %}selected{% endif %}>OFF (Always Client)</option>
    <option value="on" {% if conf.gateway == 'on' %}selected{% endif %}>ON (Force Server)</option>
  </select>

  <label>IP Mode</label>
  <select name="ip_mode">
    <option value="smart" {% if conf.ip_mode == 'smart' %}selected{% endif %}>Smart (Auto-Detect)</option>
    <option value="static" {% if conf.ip_mode == 'static' %}selected{% endif %}>Static</option>
  </select>

  <label>Static IP (If Static)</label>
  <input type="text" name="static_ip" value="{{ conf.static_ip }}">

  <button type="submit">Save & Reboot</button>
</form>
</body>
</html>
"""

@app.route('/', methods=['GET', 'POST'])
def index():
    with open(CONFIG_FILE, 'r') as f:
        conf = json.load(f)
    if request.method == 'POST':
        conf['mesh_id'] = request.form['mesh_id']
        conf['freq'] = request.form['freq']
        conf['country'] = request.form['country']
        conf['gateway'] = request.form['gateway']
        conf['ip_mode'] = request.form['ip_mode']
        conf['static_ip'] = request.form['static_ip']
        with open(CONFIG_FILE, 'w') as f:
            json.dump(conf, f, indent=4)
        subprocess.Popen(["sudo", "reboot"])
        return "Settings Saved. Rebooting..."
    return render_template_string(HTML_TEMPLATE, conf=conf)

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=80)