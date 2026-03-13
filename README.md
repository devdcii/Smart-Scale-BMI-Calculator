# Smart Scale BMI Calculator
### IoT-Based Weight and BMI Monitoring System

> A Flutter mobile app connected to an ESP32-powered smart scale for real-time weight measurement, BMI calculation, and calorie recommendations.

---

## Overview

Smart Scale BMI Calculator is a mobile app that communicates with an ESP32 microcontroller over WiFi to retrieve live weight readings. It automatically syncs weight to the user profile, calculates BMI, and provides personalized daily calorie goals based on the user's physical data and activity level.

---

## Features

- **Live Weight Monitoring** — real-time weight synced from ESP32 scale every 2 seconds
- **BMI Calculation** — auto-computed from live weight and user height
- **Weight Stability Detection** — auto-updates profile when reading stabilizes for 3 seconds
- **Calorie Calculator** — BMR and TDEE with 5 calorie goal presets
- **Macronutrient Breakdown** — protein, carbs, and fats based on daily calorie needs
- **Profile Management** — save height, age, gender, and activity level locally via Hive
- **Scale Control** — tare/reset the scale directly from the app
- **Scale Status Monitor** — uptime, sensor readiness, and connected clients
- **Onboarding Screen** — carousel intro with session persistence

---

## Tech Stack

| Layer | Technology |
|---|---|
| Mobile App | Flutter 3.x (Dart) |
| Local Storage | Hive / hive_flutter |
| HTTP Client | http ^1.5.0 |
| Microcontroller | ESP32 |
| Firmware | Arduino (C++) |
| Weight Sensor | HX711 + Load Cell |
| Communication | WiFi (ESP32 Access Point) |
| Data Format | JSON / REST |

---

## Project Structure

```
smart-scale-bmi/
├── app/                              # Flutter Mobile App
│   ├── lib/
│   │   ├── screens/
│   │   │   └── mainscreen.dart       # All screens (Dashboard, Profile, Calories, Scale)
│   │   └── main.dart                 # Entry point, Hive init, routing
│   ├── assets/
│   │   ├── images/
│   │   │   └── bghome.jfif
│   │   └── icon/
│   │       └── icon.png
│   └── pubspec.yaml
│
└── firmware/                         # ESP32 Arduino Code
    └── smart_scale/
        └── smart_scale.ino           # Main firmware file
```

---

## Hardware

### Components

| Component | Purpose |
|---|---|
| ESP32 | Main microcontroller with WiFi |
| HX711 | Load cell amplifier / ADC |
| Load Cell | Weight measurement sensor |

### Wiring

| HX711 Pin | ESP32 Pin |
|---|---|
| DOUT | D15 (GPIO 15) |
| SCK | D5 (GPIO 5) |
| VCC | 3.3V or 5V |
| GND | GND |

### ESP32 WiFi Setup

The ESP32 runs as a **WiFi Access Point** — no router needed. The mobile phone connects directly to it.

| Setting | Value |
|---|---|
| SSID | DevCpE |
| Password | 12345678 |
| ESP32 IP | 192.168.4.1 |

### ESP32 HTTP API

Base URL: `http://192.168.4.1`

| Endpoint | Method | Description |
|---|---|---|
| `/weight` | GET | Get current weight in kg |
| `/tare` | POST | Zero / reset the scale |
| `/status` | GET | Device uptime, sensor status, connected clients |
| `/config` | POST | Update calibration factor |
| `/` | GET | Web control panel (browser) |

### Calibration

The calibration factor is set in the firmware:

```cpp
float calibration_factor = 27.4; // Adjust this for your load cell
```

To calibrate: place a known weight on the scale, read the raw value from the serial monitor, and adjust `calibration_factor` until the reading matches.

### Arduino IDE Setup

1. Install **Arduino IDE** and add ESP32 board support
   - Board Manager URL: `https://dl.espressif.com/dl/package_esp32_index.json`
2. Install required libraries via Library Manager:
   - `HX711` by Bogdan Necula
   - `ArduinoJson` by Benoit Blanchon
3. Open `firmware/smart_scale/smart_scale.ino`
4. Set your WiFi credentials if changing from defaults:
```cpp
const char* ssid = "DevCpE";
const char* password = "12345678";
```
5. Select board: **ESP32 Dev Module**
6. Upload to ESP32
7. Open Serial Monitor at **115200 baud** to verify startup and weight readings

---

## Mobile App Setup

### Prerequisites

- Flutter SDK 3.0+
- Dart SDK 3.0+
- Android Studio or VS Code with Flutter extensions

### Installation

```bash
cd app
flutter pub get
flutter run
```

### Connecting to the Scale

1. Power on the ESP32
2. On your phone, connect to WiFi: **DevCpE** (password: `12345678`)
3. Open the app — the Scale tab will show **Connected** when the ESP32 is reachable
4. Weight updates automatically every 2 seconds

---

## App Screens

| Screen | Description |
|---|---|
| Dashboard | Live weight, BMI card with status, height and age summary |
| Profile | Enter height, age, gender, activity level — weight auto-fills from scale |
| Calories | BMR, TDEE, 5 calorie goal presets, macronutrient breakdown |
| Scale | Live weight display, tare button, refresh, scale status info |

---

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  cupertino_icons: ^1.0.8
  hive_flutter: ^1.1.0
  http: ^1.5.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  flutter_lints: ^5.0.0
  flutter_launcher_icons: ^0.14.4
```

---

## Color Palette

| Token | Hex | Usage |
|---|---|---|
| Primary | `#1E3A8A` (blue[900]) | Headers, buttons, accents |
| Background | `#F9FAFB` | App background |
| Success | `#22C55E` | Connected status, stable weight |
| Warning | `#F97316` | TDEE display, stable syncing |
| Error | `#EF4444` | Disconnected, obese BMI range |

---

## Developers

- Digman, Christian D.

---

## Roadmap

- [ ] Historical weight tracking with charts
- [ ] Multiple user profiles
- [ ] Weight goal setting and progress tracking
- [ ] Export data to CSV
- [ ] Notification when weight stabilizes
- [ ] OTA firmware update support
