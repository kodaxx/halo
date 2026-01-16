#!/usr/bin/env python3
"""
Halo Web Admin Panel
Modernized for Python 3 and Linux 6.12+

Changes from legacy version:
- Explicit Python 3 shebang
- Improved error handling
- Security improvements (input validation)
- Better logging
"""

from flask import Flask, request, render_template_string
import json
import subprocess
import os
import logging
from datetime import datetime

# Setup logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

app = Flask(__name__)
CONFIG_FILE = "/boot/halo.json"

HTML_TEMPLATE = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Halo Admin Panel</title>
<style>
  * { box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
    background: #222;
    color: #fff;
    padding: 20px;
    margin: 0;
  }
  .container {
    max-width: 600px;
    margin: 0 auto;
  }
  h1 {
    text-align: center;
    margin-top: 0;
  }
  form {
    background: #333;
    padding: 20px;
    border-radius: 8px;
    box-shadow: 0 2px 10px rgba(0,0,0,0.3);
  }
  label {
    display: block;
    margin-top: 15px;
    font-weight: 600;
    margin-bottom: 5px;
  }
  input, select {
    width: 100%;
    padding: 10px;
    margin-bottom: 5px;
    background: #444;
    color: #fff;
    border: 1px solid #555;
    border-radius: 4px;
    font-family: monospace;
  }
  input:focus, select:focus {
    outline: none;
    border-color: #007bff;
    box-shadow: 0 0 0 3px rgba(0,123,255,0.25);
  }
  button {
    width: 100%;
    padding: 12px;
    background: #007bff;
    color: white;
    border: none;
    border-radius: 4px;
    font-size: 16px;
    font-weight: 600;
    margin-top: 20px;
    cursor: pointer;
    transition: background 0.2s;
  }
  button:hover {
    background: #0056b3;
  }
  button:active {
    background: #004085;
  }
  .warning {
    color: #ffcc00;
    font-size: 12px;
    margin-bottom: 10px;
    display: block;
    padding: 8px;
    background: rgba(255,204,0,0.1);
    border-left: 3px solid #ffcc00;
    border-radius: 2px;
  }
  .info {
    color: #87ceeb;
    font-size: 12px;
    margin-bottom: 10px;
    display: block;
    padding: 8px;
    background: rgba(135,206,235,0.1);
    border-left: 3px solid #87ceeb;
    border-radius: 2px;
  }
</style>
</head>
<body>
<div class="container">
  <h1>🌐 Halo Admin Panel</h1>
  <form method="POST">
    <label>Mesh ID (Network Password)</label>
    <input type="text" name="mesh_id" value="{{ conf.mesh_id }}" required>
    
    <label>Frequency / Channel</label>
    <select name="freq" id="freq_select" onchange="checkCustom()" required>
        <option value="5780" {% if conf.freq|string == '5780' %}selected{% endif %}>915 MHz (Channel 156)</option>
        <option value="5795" {% if conf.freq|string == '5795' %}selected{% endif %}>921 MHz (Channel 159)</option>
        <option value="custom" {% if conf.freq|string not in ['5780', '5795'] %}selected{% endif %}>Custom / Manual</option>
    </select>
    
    <div id="custom_freq_div" style="display: {% if conf.freq|string not in ['5780', '5795'] %}block{% else %}none{% endif %}; margin-top: 10px;">
        <label>Custom Frequency (Driver Alias Value)</label>
        <input type="number" name="custom_freq" value="{{ conf.freq }}" placeholder="5795">
        <span class="info">Required: Driver aliased frequency (e.g. 5795 = 921 MHz)</span>
    </div>

    <script>
        function checkCustom() {
            var val = document.getElementById("freq_select").value;
            var div = document.getElementById("custom_freq_div");
            var input = document.querySelector('input[name="custom_freq"]');
            
            if (val === "custom") {
                div.style.display = "block";
                // If switching to custom, keep current value if it's not one of the presets
                // Otherwise clear it
                if (input.value === "5780" || input.value === "5795") {
                    input.value = ""; 
                }
            } else {
                div.style.display = "none";
                input.value = val;
            }
        }
    </script>
    
    <label>Country Code</label>
    <input type="text" name="country" value="{{ conf.country }}" maxlength="2" pattern="[A-Z]{2}" required>
    <span class="info">ISO 3166-1 alpha-2 code (e.g., US, GB, DE)</span>
    
    <label>Internet Gateway Mode</label>
    <select name="gateway" required>
      <option value="auto" {% if conf.gateway == 'auto' %}selected{% endif %}>AUTO (Hot-Swap)</option>
      <option value="off" {% if conf.gateway == 'off' %}selected{% endif %}>OFF (Always Client)</option>
      <option value="on" {% if conf.gateway == 'on' %}selected{% endif %}>ON (Force Server)</option>
    </select>
    <span class="warning">AUTO: Enables Internet Sharing when Ethernet/USB is detected. OFF: Always mesh client. ON: Always gateway.</span>

    <label>IP Mode</label>
    <select name="ip_mode" required>
      <option value="smart" {% if conf.ip_mode == 'smart' %}selected{% endif %}>Smart (Auto-Detect)</option>
      <option value="static" {% if conf.ip_mode == 'static' %}selected{% endif %}>Static</option>
    </select>

    <label>Static IP Address (If Static)</label>
    <input type="text" name="static_ip" value="{{ conf.static_ip }}" placeholder="10.0.0.1" pattern="\\d{1,3}\.\\d{1,3}\.\\d{1,3}\.\\d{1,3}">
    <span class="info">Leave blank for auto-IP if Smart mode selected</span>

    <button type="submit">💾 Save & Reboot</button>
  </form>
</div>
</body>
</html>
"""


# Valid Frequency Options (S1G -> 5GHz Alias)
# Driver Formula: 5000 + (5 * Channel_Index)
FREQ_MAP = {
    # US S1G Channels (2MHz Bandwidth)
    'US': [
        {'label': '915 MHz (Ch 156)', 'value': 5780},  # 156 * 5 + 5000 = 5780
        {'label': '921 MHz (Ch 159)', 'value': 5795},  # 159 * 5 + 5000 = 5795
        {'label': 'Custom (Expert)', 'value': 'custom'}
    ]
}

def validate_config(config):
    """Validate configuration before saving"""
    errors = []
    
    # Validate mesh_id
    if not config.get('mesh_id') or not isinstance(config['mesh_id'], str):
        errors.append("mesh_id must be a non-empty string")
    elif len(config['mesh_id']) > 32:
        errors.append("mesh_id must be 32 characters or less")
    
    # Validate frequency (Must support Aliased 5GHz values)
    try:
        freq = int(config.get('freq', 0))
        # Allow S1G range (902-928) OR Driver Alias range (5000-6000)
        if not ((902 <= freq <= 928) or (5000 <= freq <= 6000)):
            errors.append("Frequency must be valid S1G (900s) or Aliased 5GHz (5000s)")
    except (ValueError, TypeError):
        errors.append("Frequency must be a valid number")
    
    # Validate country code
    country = config.get('country', '').upper()
    if not country or len(country) != 2:
        errors.append("Country code must be exactly 2 characters")
    elif not country.isalpha():
        errors.append("Country code must contain only letters")
    else:
        config['country'] = country
    
    # Validate gateway mode
    if config.get('gateway') not in ['auto', 'off', 'on']:
        errors.append("Gateway mode must be 'auto', 'off', or 'on'")
    
    # Validate IP mode
    if config.get('ip_mode') not in ['smart', 'static']:
        errors.append("IP mode must be 'smart' or 'static'")
    
    # Validate static IP if provided
    if config.get('static_ip'):
        parts = config['static_ip'].split('.')
        if len(parts) != 4:
            errors.append("Static IP must be a valid IPv4 address")
        else:
            try:
                for part in parts:
                    num = int(part)
                    if not (0 <= num <= 255):
                        errors.append("Each octet in IP address must be 0-255")
            except ValueError:
                errors.append("Static IP must contain only numeric octets")
    
    return errors

@app.route('/', methods=['GET', 'POST'])
def index():
    """Main admin panel endpoint"""
    try:
        with open(CONFIG_FILE, 'r') as f:
            conf = json.load(f)
    except FileNotFoundError:
        logger.error(f"Config file not found: {CONFIG_FILE}")
        return f"Error: Config file not found at {CONFIG_FILE}", 500
    except json.JSONDecodeError:
        logger.error(f"Config file is not valid JSON: {CONFIG_FILE}")
        return "Error: Config file is corrupted", 500
    
    if request.method == 'POST':
        # Get form data
        new_config = {
            'mesh_id': request.form.get('mesh_id', conf.get('mesh_id', '')),
            'freq': request.form.get('custom_freq') if request.form.get('freq') == 'custom' or request.form.get('custom_freq') else request.form.get('freq', conf.get('freq', '')),
            'country': request.form.get('country', conf.get('country', 'US')),
            'gateway': request.form.get('gateway', conf.get('gateway', 'auto')),
            'ip_mode': request.form.get('ip_mode', conf.get('ip_mode', 'smart')),
            'static_ip': request.form.get('static_ip', conf.get('static_ip', '')),
        }
        
        # Validate configuration
        errors = validate_config(new_config)
        if errors:
            logger.warning(f"Configuration validation errors: {errors}")
            return f"Configuration Error: {', '.join(errors)}", 400
        
        # Save configuration
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(new_config, f, indent=4)
            logger.info(f"Configuration saved successfully: {new_config}")
            
            # Schedule reboot
            try:
                subprocess.Popen(['sudo', 'shutdown', '-r', '+1', 'Halo admin panel reboot'])
                return "✓ Settings saved. Device will reboot in 1 minute..."
            except Exception as e:
                logger.error(f"Reboot command failed: {e}")
                return f"Settings saved, but reboot failed: {e}", 500
        except IOError as e:
            logger.error(f"Failed to write config: {e}")
            return f"Error: Could not write configuration ({e})", 500
    
    return render_template_string(HTML_TEMPLATE, conf=conf)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    try:
        with open(CONFIG_FILE, 'r') as f:
            json.load(f)
        return {'status': 'ok'}, 200
    except Exception as e:
        logger.error(f"Health check failed: {e}")
        return {'status': 'error', 'message': str(e)}, 500

if __name__ == '__main__':
    logger.info("Starting Halo Admin Panel (Python 3, Linux 6.12+)")
    logger.info(f"Config file: {CONFIG_FILE}")
    
    # Run Flask app
    # For production, use a WSGI server like gunicorn:
    # gunicorn --bind 0.0.0.0:80 --workers 2 web_admin:app
    app.run(host='0.0.0.0', port=80, debug=False)
