import processing.serial.*;

Serial arduino;

// -------------------- WINDOW --------------------
final int WINDOW_W = 1000;
final int WINDOW_H = 720;
final int BAUD_RATE = 115200;

// -------------------- SERIAL --------------------
String[] availablePorts = {};
int selectedPort = -1;
boolean portDropdownOpen = false;
boolean connected = false;

String connectionStatus = "Disconnected";
String motorStatus = "Waiting";
String positionText = "0.000 mm";
String latestLine = "";

// -------------------- UI --------------------
ArrayList<InputField> fields = new ArrayList<InputField>();

InputField distanceField;
InputField speedField;
InputField accelerationField;
InputField amplitudeField;
InputField frequencyField;
InputField durationField;

boolean presetDropdownOpen = false;
int selectedPreset = 0;

// -------------------- PRESETS --------------------
// Columns: amplitude, frequency, speed, acceleration, duration
float[][] presets = {
  {0.5, 0.25, 2, 5, 10},
  {0.5, 0.5, 3, 10, 10},
  {0.5, 1, 5, 40, 10},
  {0.5, 2, 10, 160, 10},
  {0.5, 3, 15, 350, 10},
  {0.5, 4, 20, 500, 10},
  {0.5, 5, 25, 800, 5},
  {0.5, 6, 30, 1100, 5}
};

String[] presetNames = {
  "Very slow",
  "Slow",
  "Low frequency",
  "Medium frequency",
  "Fast",
  "High frequency",
  "Very high",
  "Maximum example"
};

// -------------------- COLORS --------------------
color backgroundColor = color(22, 26, 34);
color panelColor = color(32, 38, 49);
color fieldColor = color(43, 50, 64);
color accentColor = color(55, 145, 220);
color greenColor = color(60, 185, 125);
color redColor = color(220, 75, 75);
color textColor = color(235, 240, 248);
color mutedColor = color(150, 160, 175);

// -------------------- SETUP --------------------
void setup() {
  size(1000, 720);
  surface.setTitle("Stepper Motor Test Controller");
  surface.setResizable(false);

  textFont(createFont("Arial", 15));

  // Position input fields with correct vertical clearance from section titles
  distanceField = new InputField(70, 225, 250, 38,
    "Distance (mm)", "10");

  speedField = new InputField(350, 225, 250, 38,
    "Speed (mm/s)", "10");

  accelerationField = new InputField(630, 225, 250, 38,
    "Acceleration (mm/s²)", "100");

  amplitudeField = new InputField(70, 355, 250, 38,
    "Amplitude (mm)", "0.5");

  frequencyField = new InputField(350, 355, 250, 38,
    "Frequency (Hz)", "1");

  durationField = new InputField(630, 355, 250, 38,
    "Test time (seconds)", "10");

  fields.add(distanceField);
  fields.add(speedField);
  fields.add(accelerationField);
  fields.add(amplitudeField);
  fields.add(frequencyField);
  fields.add(durationField);

  refreshPorts();
}

// -------------------- DRAW --------------------
void draw() {
  background(backgroundColor);

  processSerialLine();

  drawHeader();
  drawConnectionPanel();
  drawMotionPanel();
  drawVibrationPanel();
  drawControlButtons();
  drawStatusPanel();

  // Draw dropdowns last so they render cleanly on top of all panels
  if (portDropdownOpen) {
    drawPortDropdown();
  }
  if (presetDropdownOpen) {
    drawPresetDropdown();
  }
}

// -------------------- HEADER --------------------
void drawHeader() {
  fill(textColor);
  textSize(24);
  text("STEPPER MOTOR TEST CONTROLLER", 40, 38);

  fill(mutedColor);
  textSize(13);
  text("Arduino Uno  |  TB6600  |  Processing 4", 42, 58);
}

// -------------------- CONNECTION PANEL --------------------
void drawConnectionPanel() {
  drawPanel(40, 75, 920, 85);

  fill(textColor);
  textSize(15);
  text("SERIAL CONNECTION", 65, 100);

  // COM dropdown trigger box
  fill(fieldColor);
  rect(65, 113, 260, 35, 7);

  fill(textColor);
  textSize(13);

  String portLabel = "Select COM port";
  if (selectedPort >= 0 && selectedPort < availablePorts.length) {
    portLabel = availablePorts[selectedPort];
  }

  text(portLabel, 80, 134);
  text("▼", 300, 134);

  drawButton(345, 113, 105, 35, "Refresh", accentColor);
  drawButton(465, 113, 120, 35,
    connected ? "Disconnect" : "Connect",
    connected ? redColor : greenColor);

  fill(mutedColor);
  textSize(12);
  text(connectionStatus, 610, 134);
}

void drawPortDropdown() {
  int listX = 65;
  int listY = 150;
  int listW = 260;
  int itemHeight = 30;
  int totalH = max(30, availablePorts.length * itemHeight);

  // Dropdown background shadow/outline
  fill(20, 24, 32);
  rect(listX - 1, listY - 1, listW + 2, totalH + 2, 6);

  fill(fieldColor);
  rect(listX, listY, listW, totalH, 5);

  if (availablePorts.length == 0) {
    fill(mutedColor);
    textSize(13);
    text("No COM ports found", listX + 15, listY + 20);
  } else {
    for (int i = 0; i < availablePorts.length; i++) {
      if (i == selectedPort) {
        fill(accentColor);
        rect(listX, listY + i * itemHeight, listW, itemHeight);
      }

      fill(textColor);
      textSize(13);
      text(availablePorts[i], listX + 15, listY + i * itemHeight + 20);
    }
  }
}

// -------------------- MOTION PANEL --------------------
void drawMotionPanel() {
  drawPanel(40, 175, 920, 105);

  fill(textColor);
  textSize(15);
  text("POSITION / MOTION TEST", 65, 200);

  for (InputField f : fields) {
    if (f == distanceField || f == speedField ||
        f == accelerationField) {
      f.display();
    }
  }
}

// -------------------- VIBRATION PANEL --------------------
void drawVibrationPanel() {
  drawPanel(40, 295, 920, 140);

  fill(textColor);
  textSize(15);
  text("VIBRATION TEST", 65, 320);

  for (InputField f : fields) {
    if (f == amplitudeField || f == frequencyField ||
        f == durationField) {
      f.display();
    }
  }

  // Preset dropdown trigger box
  fill(fieldColor);
  rect(70, 397, 250, 30, 6);

  fill(textColor);
  textSize(12);
  text("Preset: " + presetNames[selectedPreset], 82, 416);
  text("▼", 295, 416);
}

void drawPresetDropdown() {
  int listX = 70;
  int listY = 430;
  int listW = 250;
  int h = 26;
  int totalH = presetNames.length * h;

  fill(20, 24, 32);
  rect(listX - 1, listY - 1, listW + 2, totalH + 2, 6);

  fill(fieldColor);
  rect(listX, listY, listW, totalH, 5);

  for (int i = 0; i < presetNames.length; i++) {
    if (i == selectedPreset) {
      fill(accentColor);
      rect(listX, listY + i * h, listW, h);
    }

    fill(textColor);
    textSize(12);
    text(presetNames[i], listX + 12, listY + i * h + 18);
  }
}

// -------------------- BUTTONS --------------------
void drawControlButtons() {
  drawPanel(40, 450, 920, 85);

  fill(textColor);
  textSize(15);
  text("MOTOR CONTROLS", 65, 475);

  drawButton(65, 488, 140, 33, "Forward", greenColor);
  drawButton(220, 488, 140, 33, "Backward", accentColor);
  drawButton(375, 488, 170, 33, "Start Vibration", accentColor);
  drawButton(560, 488, 110, 33, "STOP", redColor);
  drawButton(685, 488, 110, 33, "Zero", fieldColor);
  drawButton(810, 488, 110, 33, "Query", fieldColor);
}

// -------------------- STATUS PANEL --------------------
void drawStatusPanel() {
  drawPanel(40, 550, 920, 75);

  fill(textColor);
  textSize(15);
  text("SYSTEM STATUS", 65, 575);

  fill(mutedColor);
  textSize(13);
  text("Motor: " + motorStatus, 65, 603);
  text("Position: " + positionText, 350, 603);
  text("Last message: " + latestLine, 610, 603);
}

// -------------------- COMMON UI --------------------
void drawPanel(float x, float y, float w, float h) {
  noStroke();
  fill(panelColor);
  rect(x, y, w, h, 10);
}

void drawButton(float x, float y, float w, float h,
                String label, color buttonColor) {
  noStroke();
  fill(buttonColor);
  rect(x, y, w, h, 6);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(13);
  text(label, x + w/2, y + h/2);
  textAlign(LEFT, BASELINE);
}

// -------------------- PORT MANAGEMENT --------------------
void refreshPorts() {
  availablePorts = Serial.list();

  if (availablePorts.length == 0) {
    selectedPort = -1;
  } else {
    selectedPort = 0;
  }

  connectionStatus = availablePorts.length + " serial port(s) found";
}

void connectArduino() {
  if (connected) return;

  if (selectedPort < 0 ||
      selectedPort >= availablePorts.length) {
    connectionStatus = "Select a COM port first";
    return;
  }

  try {
    arduino = new Serial(this, availablePorts[selectedPort], BAUD_RATE);
    arduino.clear();
    arduino.bufferUntil('\n');

    connected = true;
    connectionStatus = "Connected: " + availablePorts[selectedPort];

    delay(1500);
    sendCommand("Q");

  } catch (Exception e) {
    connected = false;
    connectionStatus = "Connection failed: " + e.getMessage();
  }
}

void disconnectArduino() {
  if (arduino != null) {
    arduino.stop();
    arduino = null;
  }

  connected = false;
  connectionStatus = "Disconnected";
}

// -------------------- SERIAL COMMUNICATION --------------------
void sendCommand(String command) {
  if (!connected || arduino == null) {
    connectionStatus = "Not connected";
    return;
  }

  arduino.write(command + "\n");
  println("TX: " + command);
}

void serialEvent(Serial port) {
  String line = port.readStringUntil('\n');

  if (line != null) {
    latestLine = trim(line);
  }
}

void processSerialLine() {
  if (latestLine.length() == 0) return;

  String line = latestLine;

  if (line.startsWith("POS,")) {
    String[] parts = split(line, ',');
    if (parts.length > 1) {
      positionText = parts[1] + " mm";
    }
  } else if (line.equals("BUSY")) {
    motorStatus = "Moving";
  } else if (line.equals("DONE")) {
    motorStatus = "Finished";
  } else if (line.equals("STOPPING")) {
    motorStatus = "Stopping";
  } else if (line.startsWith("ERROR")) {
    motorStatus = line;
  } else if (line.equals("RETURNING")) {
    motorStatus = "Returning to center";
  }
}

// -------------------- INPUT VALIDATION --------------------
float getValue(InputField field) {
  try {
    return Float.parseFloat(field.value);
  } catch (Exception e) {
    return Float.NaN;
  }
}

boolean validMotionInputs() {
  float d = getValue(distanceField);
  float s = getValue(speedField);
  float a = getValue(accelerationField);

  if (Float.isNaN(d) || Float.isNaN(s) ||
      Float.isNaN(a) || d == 0 || s <= 0 || a <= 0) {
    motorStatus = "Invalid motion parameters";
    return false;
  }

  return true;
}

boolean validVibrationInputs() {
  float amplitude = getValue(amplitudeField);
  float frequency = getValue(frequencyField);
  float duration = getValue(durationField);
  float speed = getValue(speedField);
  float acceleration = getValue(accelerationField);

  if (Float.isNaN(amplitude) || Float.isNaN(frequency) ||
      Float.isNaN(duration) || Float.isNaN(speed) ||
      Float.isNaN(acceleration) ||
      amplitude <= 0 || frequency <= 0 || duration <= 0 ||
      speed <= 0 || acceleration <= 0) {
    motorStatus = "Invalid vibration parameters";
    return false;
  }

  return true;
}

// -------------------- COMMANDS --------------------
void moveForward() {
  if (!validMotionInputs()) return;

  float d = abs(getValue(distanceField));
  sendCommand("M," + d + "," +
    getValue(speedField) + "," +
    getValue(accelerationField));

  motorStatus = "Forward command sent";
}

void moveBackward() {
  if (!validMotionInputs()) return;

  float d = -abs(getValue(distanceField));
  sendCommand("M," + d + "," +
    getValue(speedField) + "," +
    getValue(accelerationField));

  motorStatus = "Backward command sent";
}

void startVibration() {
  if (!validVibrationInputs()) return;

  sendCommand("V," +
    getValue(amplitudeField) + "," +
    getValue(frequencyField) + "," +
    getValue(durationField) + "," +
    getValue(speedField) + "," +
    getValue(accelerationField));

  motorStatus = "Vibration test started";
}

// -------------------- PRESET --------------------
void applyPreset(int index) {
  selectedPreset = index;

  amplitudeField.value = str(presets[index][0]);
  frequencyField.value = str(presets[index][1]);
  speedField.value = str(presets[index][2]);
  accelerationField.value = str(presets[index][3]);
  durationField.value = str(presets[index][4]);
}

// -------------------- MOUSE INPUT --------------------
void mousePressed() {
  boolean clickedPort = mouseX >= 65 && mouseX <= 325 &&
                        mouseY >= 113 && mouseY <= 148;

  boolean clickedPreset = mouseX >= 70 && mouseX <= 320 &&
                          mouseY >= 397 && mouseY <= 427;

  // COM dropdown selection handling
  if (portDropdownOpen) {
    int index = (mouseY - 150) / 30;

    if (mouseX >= 65 && mouseX <= 325 &&
        index >= 0 && index < availablePorts.length) {
      selectedPort = index;
    }

    portDropdownOpen = false;
    return;
  }

  // Preset dropdown selection handling
  if (presetDropdownOpen) {
    int index = (mouseY - 430) / 26;

    if (mouseX >= 70 && mouseX <= 320 &&
        index >= 0 && index < presets.length) {
      applyPreset(index);
    }

    presetDropdownOpen = false;
    return;
  }

  // Toggle COM dropdown
  if (clickedPort) {
    portDropdownOpen = !portDropdownOpen;
    presetDropdownOpen = false;
    return;
  }

  // Toggle Preset dropdown
  if (clickedPreset) {
    presetDropdownOpen = !presetDropdownOpen;
    portDropdownOpen = false;
    return;
  }

  // Refresh button
  if (inside(345, 113, 105, 35)) {
    refreshPorts();
    return;
  }

  // Connect button
  if (inside(465, 113, 120, 35)) {
    if (connected) {
      disconnectArduino();
    } else {
      connectArduino();
    }
    return;
  }

  // Input fields focus
  boolean fieldClicked = false;
  for (InputField f : fields) {
    if (f.contains(mouseX, mouseY)) {
      for (InputField other : fields) {
        other.active = false;
      }
      f.active = true;
      fieldClicked = true;
    }
  }

  if (fieldClicked) return;

  for (InputField f : fields) {
    f.active = false;
  }

  // Motor buttons
  if (inside(65, 488, 140, 33)) {
    moveForward();
  } else if (inside(220, 488, 140, 33)) {
    moveBackward();
  } else if (inside(375, 488, 170, 33)) {
    startVibration();
  } else if (inside(560, 488, 110, 33)) {
    sendCommand("S");
    motorStatus = "Stop requested";
  } else if (inside(685, 488, 110, 33)) {
    sendCommand("Z");
    motorStatus = "Zero requested";
  } else if (inside(810, 488, 110, 33)) {
    sendCommand("Q");
  }
}

boolean inside(float x, float y, float w, float h) {
  return mouseX >= x && mouseX <= x+w &&
         mouseY >= y && mouseY <= y+h;
}

// -------------------- KEYBOARD INPUT --------------------
void keyPressed() {
  for (InputField f : fields) {
    if (f.active) {
      f.handleKey(key, keyCode);
      return;
    }
  }
}

// -------------------- INPUT FIELD CLASS --------------------
class InputField {
  float x, y, w, h;
  String label;
  String value;
  boolean active = false;

  InputField(float x, float y, float w, float h,
             String label, String value) {
    this.x = x;
    this.y = y;
    this.w = w;
    this.h = h;
    this.label = label;
    this.value = value;
  }

  void display() {
    fill(mutedColor);
    textSize(12);
    text(label, x, y - 6);

    fill(active ? color(55, 75, 105) : fieldColor);
    stroke(active ? accentColor : color(65, 75, 90));
    rect(x, y, w, h, 6);
    noStroke();

    fill(textColor);
    textSize(14);
    text(value, x + 12, y + 24);
  }

  boolean contains(float mx, float my) {
    return mx >= x && mx <= x+w &&
           my >= y && my <= y+h;
  }

  void handleKey(char k, int code) {
    if (code == BACKSPACE) {
      if (value.length() > 0) {
        value = value.substring(0, value.length()-1);
      }
    } else if (code == DELETE) {
      value = "";
    } else if (k == ENTER || k == RETURN) {
      active = false;
    } else if ((k >= '0' && k <= '9') ||
               k == '.' || k == '-') {
      value += k;
    }
  }
}
