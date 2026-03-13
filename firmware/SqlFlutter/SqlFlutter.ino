#include <WiFi.h>
#include <WebServer.h>
#include <ArduinoJson.h>
#include "HX711.h"

// HX711 circuit wiring
const int LOADCELL_DOUT_PIN = 15;  // D15
const int LOADCELL_SCK_PIN = 5;    // D5

// WiFi credentials for Access Point
const char* ssid = "DevCpE";
const char* password = "12345678";

// Initialize HX711 and WebServer
HX711 scale;
WebServer server(80);

// Calibration factor - use the value you found during calibration
float calibration_factor = 27.4; // Replace with your calibrated value

// Variables for weight management
float current_weight = 0.0;
unsigned long last_weight_update = 0;
const unsigned long WEIGHT_UPDATE_INTERVAL = 1000; // Update every 1 second

void setup() {
  Serial.begin(115200);
  Serial.println("Smart Scale ESP32 Server Starting...");
  
  // Initialize HX711
  scale.begin(LOADCELL_DOUT_PIN, LOADCELL_SCK_PIN);
  scale.set_scale(calibration_factor);
  scale.tare(); // Reset to zero
  
  Serial.println("HX711 initialized and tared");
  
  // Setup WiFi Access Point
  WiFi.softAP(ssid, password);
  IPAddress IP = WiFi.softAPIP();
  Serial.print("AP IP address: ");
  Serial.println(IP);
  Serial.println("WiFi: SmartScale_WiFi");
  Serial.println("Password: scale123456");
  
  // Setup web server routes
  setupServerRoutes();
  
  // Start server
  server.begin();
  Serial.println("HTTP server started");
  Serial.println("Ready to serve weight data!");
  Serial.println("=================================");
}

void setupServerRoutes() {
  // CORS headers for all responses
  server.onNotFound([]() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(404, "text/plain", "Not Found");
  });

  // Handle preflight OPTIONS requests
  server.on("/weight", HTTP_OPTIONS, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200, "text/plain", "");
  });

  server.on("/tare", HTTP_OPTIONS, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200, "text/plain", "");
  });

  server.on("/status", HTTP_OPTIONS, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    server.send(200, "text/plain", "");
  });

  // Main route - Get current weight
  server.on("/weight", HTTP_GET, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    
    // Get fresh weight reading
    updateWeight();
    
    // Create JSON response
    DynamicJsonDocument doc(200);
    doc["weight"] = current_weight;
    doc["unit"] = "kg";
    doc["timestamp"] = millis();
    doc["status"] = "success";
    
    String response;
    serializeJson(doc, response);
    
    server.send(200, "application/json", response);
    
    Serial.print("Weight requested: ");
    Serial.print(current_weight, 2);
    Serial.println(" kg");
  });

  // Tare the scale (reset to zero)
  server.on("/tare", HTTP_POST, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    
    Serial.println("Tare requested - zeroing scale...");
    scale.tare(20); // Take 20 readings for accurate tare
    
    DynamicJsonDocument doc(200);
    doc["status"] = "success";
    doc["message"] = "Scale tared successfully";
    doc["timestamp"] = millis();
    
    String response;
    serializeJson(doc, response);
    
    server.send(200, "application/json", response);
    Serial.println("Scale tared successfully");
  });

  // Status check endpoint
  server.on("/status", HTTP_GET, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    
    DynamicJsonDocument doc(300);
    doc["status"] = "online";
    doc["device"] = "Smart Scale ESP32";
    doc["version"] = "1.0";
    doc["uptime"] = millis();
    doc["calibration_factor"] = calibration_factor;
    doc["hx711_ready"] = scale.is_ready();
    doc["clients_connected"] = WiFi.softAPgetStationNum();
    
    String response;
    serializeJson(doc, response);
    
    server.send(200, "application/json", response);
    Serial.println("Status check requested");
  });

  // Configuration endpoint to update calibration factor
  server.on("/config", HTTP_POST, []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    server.sendHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
    server.sendHeader("Access-Control-Allow-Headers", "Content-Type");
    
    if (server.hasArg("calibration_factor")) {
      float new_factor = server.arg("calibration_factor").toFloat();
      if (new_factor != 0) {
        calibration_factor = new_factor;
        scale.set_scale(calibration_factor);
        
        DynamicJsonDocument doc(200);
        doc["status"] = "success";
        doc["message"] = "Calibration factor updated";
        doc["new_factor"] = calibration_factor;
        
        String response;
        serializeJson(doc, response);
        server.send(200, "application/json", response);
        
        Serial.print("Calibration factor updated to: ");
        Serial.println(calibration_factor);
      } else {
        server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Invalid calibration factor\"}");
      }
    } else {
      server.send(400, "application/json", "{\"status\":\"error\",\"message\":\"Missing calibration_factor parameter\"}");
    }
  });

  // Root page with simple web interface
  server.on("/", []() {
    server.sendHeader("Access-Control-Allow-Origin", "*");
    String html = generateWebInterface();
    server.send(200, "text/html", html);
  });
}

void updateWeight() {
  if (scale.is_ready()) {
    // Get weight reading (average of 5 readings for stability)
    float weight_grams = scale.get_units(5);
    current_weight = weight_grams / 1000.0; // Convert to kg
    
    // Ensure positive readings
    if (current_weight < 0) {
      current_weight = abs(current_weight);
    }
    
    // Filter out very small readings (noise)
    if (current_weight < 0.1) {
      current_weight = 0.0;
    }
  } else {
    Serial.println("HX711 not ready!");
  }
}

String generateWebInterface() {
  String html = R"rawliteral(
<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Smart Scale Control</title>
    <style>
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            margin: 0;
            padding: 20px;
            background: linear-gradient(135deg, #1e3c72 0%, #2a5298 100%);
            min-height: 100vh;
            color: white;
        }
        .container {
            max-width: 600px;
            margin: 0 auto;
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 30px;
            box-shadow: 0 8px 32px 0 rgba(31, 38, 135, 0.37);
        }
        .header {
            text-align: center;
            margin-bottom: 30px;
        }
        .weight-display {
            text-align: center;
            font-size: 3em;
            font-weight: bold;
            margin: 30px 0;
            padding: 20px;
            background: rgba(255, 255, 255, 0.2);
            border-radius: 15px;
        }
        .controls {
            display: flex;
            gap: 15px;
            justify-content: center;
            flex-wrap: wrap;
        }
        button {
            padding: 12px 24px;
            border: none;
            border-radius: 10px;
            background: rgba(255, 255, 255, 0.2);
            color: white;
            font-weight: bold;
            cursor: pointer;
            transition: all 0.3s ease;
        }
        button:hover {
            background: rgba(255, 255, 255, 0.3);
            transform: translateY(-2px);
        }
        .status {
            margin-top: 20px;
            padding: 15px;
            background: rgba(255, 255, 255, 0.1);
            border-radius: 10px;
            text-align: center;
        }
        .auto-refresh {
            margin: 20px 0;
            text-align: center;
        }
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Smart Scale Control Panel</h1>
            <p>ESP32 Weight Scale Interface</p>
        </div>
        
        <div class="weight-display" id="weightDisplay">
            -- kg
        </div>
        
        <div class="auto-refresh">
            <label>
                <input type="checkbox" id="autoRefresh" checked> Auto-refresh every 2 seconds
            </label>
        </div>
        
        <div class="controls">
            <button onclick="getWeight()">Get Weight</button>
            <button onclick="tareScale()">Tare Scale</button>
            <button onclick="getStatus()">Check Status</button>
        </div>
        
        <div class="status" id="statusDiv">
            Click "Check Status" for system information
        </div>
    </div>

    <script>
        let autoRefreshInterval;
        
        // Auto-refresh functionality
        document.getElementById('autoRefresh').addEventListener('change', function(e) {
            if (e.target.checked) {
                startAutoRefresh();
            } else {
                stopAutoRefresh();
            }
        });
        
        function startAutoRefresh() {
            autoRefreshInterval = setInterval(getWeight, 2000);
            getWeight(); // Get initial reading
        }
        
        function stopAutoRefresh() {
            if (autoRefreshInterval) {
                clearInterval(autoRefreshInterval);
                autoRefreshInterval = null;
            }
        }
        
        async function getWeight() {
            try {
                const response = await fetch('/weight');
                const data = await response.json();
                document.getElementById('weightDisplay').innerHTML = data.weight.toFixed(2) + ' kg';
            } catch (error) {
                document.getElementById('weightDisplay').innerHTML = 'Error reading weight';
                console.error('Error:', error);
            }
        }
        
        async function tareScale() {
            try {
                const response = await fetch('/tare', { method: 'POST' });
                const data = await response.json();
                document.getElementById('statusDiv').innerHTML = 
                    '<strong>Tare Result:</strong> ' + data.message;
                setTimeout(getWeight, 2000); // Get weight after tare
            } catch (error) {
                document.getElementById('statusDiv').innerHTML = 'Error taring scale';
                console.error('Error:', error);
            }
        }
        
        async function getStatus() {
            try {
                const response = await fetch('/status');
                const data = await response.json();
                document.getElementById('statusDiv').innerHTML = 
                    '<strong>Status:</strong> ' + data.status + '<br>' +
                    '<strong>Device:</strong> ' + data.device + '<br>' +
                    '<strong>Uptime:</strong> ' + Math.floor(data.uptime / 1000) + ' seconds<br>' +
                    '<strong>HX711 Ready:</strong> ' + (data.hx711_ready ? 'Yes' : 'No') + '<br>' +
                    '<strong>Connected Clients:</strong> ' + data.clients_connected;
            } catch (error) {
                document.getElementById('statusDiv').innerHTML = 'Error getting status';
                console.error('Error:', error);
            }
        }
        
        // Start auto-refresh when page loads
        window.addEventListener('load', function() {
            startAutoRefresh();
        });
        
        // Stop auto-refresh when page is about to unload
        window.addEventListener('beforeunload', function() {
            stopAutoRefresh();
        });
    </script>
</body>
</html>
)rawliteral";
  return html;
}

void loop() {
  // Handle client requests
  server.handleClient();
  
  // Update weight reading periodically
  unsigned long currentTime = millis();
  if (currentTime - last_weight_update >= WEIGHT_UPDATE_INTERVAL) {
    updateWeight();
    last_weight_update = currentTime;
  }
  
  // Print weight to serial every 5 seconds for debugging
  static unsigned long last_serial_print = 0;
  if (currentTime - last_serial_print >= 5000) {
    Serial.print("Current weight: ");
    Serial.print(current_weight, 2);
    Serial.print(" kg | Connected clients: ");
    Serial.println(WiFi.softAPgetStationNum());
    last_serial_print = currentTime;
  }
  
  // Small delay to prevent WDT reset
  delay(10);
}