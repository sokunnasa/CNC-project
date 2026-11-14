
import processing.serial.*;

// =====================================
// OpenCNC - Processing 4 Prototype v0.1
// =====================================

Serial serial;

String machineMode = "CNC";
String status = "Disconnected";

String[] ports;
String selectedPort = "";

float x = 0;
float y = 0;
float z = 0;

float jogStep = 1;
boolean connected = false;
boolean spindle = false;
boolean emergency = false;
boolean running = false;

String gcode = "G21\nG90\nG0 X10 Y10\nG1 Z-2 F100\nG0 Z10";
String[] commands;
int commandIndex = 0;

// UI colors
color bg = color(28, 32, 39);
color panel = color(43, 49, 59);
color blue = color(45, 120, 210);
color green = color(40, 160, 100);
color red = color(190, 55, 55);

void setup() {
  size(1100, 750);
  textFont(createFont("Arial", 14));

  refreshPorts();
}

void draw() {
  background(bg);

  drawHeader();
  drawConnection();
  drawMachineControl();
  drawVisualization();
  drawGcode();
  drawFooter();
}

// =====================================
// HEADER
// =====================================

void drawHeader() {
  fill(255);
  textSize(24);
  text("OpenCNC", 20, 32);

  textSize(12);
  fill(160);
  text("OPEN-SOURCE MACHINE CONTROL PLATFORM", 20, 52);

  fill(panel);
  rect(0, 70, width, 45);

  drawButton(20, 78, 120, 28, "CNC MODE",
    machineMode.equals("CNC") ? blue : panel);

  drawButton(150, 78, 150, 28, "3D PRINTER",
    machineMode.equals("3D PRINTER") ? blue : panel);

  fill(connected ? green : red);
  ellipse(1030, 92, 10, 10);

  fill(255);
  textAlign(RIGHT);
  text(status, 1015, 96);
  textAlign(LEFT);
}

// =====================================
// CONNECTION
// =====================================

void drawConnection() {
  drawPanel(20, 130, 340, 125, "CONNECTION");

  fill(200);
  text("Available Serial Ports:", 35, 175);

  fill(255);
  rect(35, 185, 180, 30, 4);

  fill(30);
  text(selectedPort.equals("") ? "No port selected" :
    selectedPort, 45, 205);

  drawButton(225, 185, 115, 30, "Refresh", blue);

  drawButton(35, 220, 145, 27,
    connected ? "Disconnect" : "Connect",
    connected ? red : green);

  drawButton(190, 220, 150, 27, "Select Next Port", panel);
}

// =====================================
// MACHINE CONTROL
// =====================================

void drawMachineControl() {
  drawPanel(20, 275, 340, 360, "MANUAL MACHINE CONTROL");

  fill(200);
  text("Jog Distance:", 35, 325);

  String[] steps = {"0.1", "1", "10", "100"};

  for (int i = 0; i < steps.length; i++) {
    drawButton(35+i*75, 340, 65, 30, steps[i],
      jogStep == float(steps[i]) ? blue : panel);
  }

  // XY movement
  drawButton(125, 395, 65, 45, "Y+", panel);
  drawButton(55, 445, 65, 45, "X-", panel);
  drawButton(125, 445, 65, 45, "HOME", blue);
  drawButton(195, 445, 65, 45, "X+", panel);
  drawButton(125, 495, 65, 45, "Y-", panel);

  // Z movement
  drawButton(270, 395, 65, 45, "Z+", panel);
  drawButton(270, 445, 65, 45, "Z-", panel);

  fill(200);
  text("Coordinates (mm)", 35, 580);

  fill(255);
  text("X: " + nf(x, 0, 2), 35, 605);
  text("Y: " + nf(y, 0, 2), 130, 605);
  text("Z: " + nf(z, 0, 2), 225, 605);
}

// =====================================
// VISUALIZATION
// =====================================

void drawVisualization() {
  drawPanel(380, 130, 700, 330, "MACHINE VISUALIZATION");

  float cx = 730;
  float cy = 300;

  // Workspace
  stroke(90);
  noFill();
  rect(cx-180, cy-100, 360, 200);

  // Grid
  stroke(65);
  for (int i = -150; i <= 150; i += 30) {
    line(cx+i, cy-100, cx+i, cy+100);
  }

  for (int i = -90; i <= 90; i += 30) {
    line(cx-180, cy+i, cx+180, cy+i);
  }

  // Axis
  stroke(255, 80, 80);
  line(cx, cy, cx+70, cy);

  stroke(80, 255, 120);
  line(cx, cy, cx, cy-70);

  // Tool position
  float px = cx + constrain(x, -180, 180);
  float py = cy - constrain(y, -100, 100);

  noStroke();
  fill(blue);
  ellipse(px, py, 15, 15);

  fill(255);
  text("Tool / Spindle Position", 395, 440);

  fill(180);
  text("Z Height: " + nf(z, 0, 2) + " mm", 800, 440);
}

// =====================================
// GCODE
// =====================================

void drawGcode() {
  drawPanel(380, 480, 700, 155, "G-CODE TERMINAL");

  fill(255);
  textSize(13);

  String[] lines = split(gcode, '\n');

  for (int i = 0; i < min(lines.length, 5); i++) {
    fill(i == commandIndex && running ? green : 200);
    text(lines[i], 400, 525+i*20);
  }

  drawButton(800, 590, 80, 30,
    running ? "Running" : "Run", green);

  drawButton(890, 590, 80, 30, "Stop", red);

  drawButton(980, 590, 80, 30, "Reset", panel);
}

// =====================================
// FOOTER
// =====================================

void drawFooter() {
  fill(130);
  textSize(12);
  text("OpenCNC v0.1 | Processing 4 | Prototype",
    20, 715);

  fill(emergency ? red : 130);
  text(emergency ? "EMERGENCY STOP ACTIVE" :
    "SYSTEM READY", 850, 715);

  drawButton(900, 660, 160, 40,
    "EMERGENCY STOP", red);
}

// =====================================
// BUTTON / PANEL
// =====================================

void drawPanel(int px, int py, int w, int h, String title) {
  noStroke();
  fill(panel);
  rect(px, py, w, h, 8);

  fill(255);
  textSize(15);
  text(title, px+15, py+25);
}

void drawButton(int px, int py, int w, int h,
                String label, color c) {
  noStroke();
  fill(c);
  rect(px, py, w, h, 5);

  fill(255);
  textAlign(CENTER, CENTER);
  textSize(12);
  text(label, px+w/2, py+h/2);

  textAlign(LEFT, BASELINE);
}

// =====================================
// SERIAL PORTS
// =====================================

void refreshPorts() {
  ports = Serial.list();

  if (ports.length > 0) {
    selectedPort = ports[0];
  } else {
    selectedPort = "";
  }
}

// =====================================
// MOUSE INTERACTION
// =====================================

void mousePressed() {

  if (mouseX > 900 && mouseX < 1060 &&
      mouseY > 660 && mouseY < 700) {
    emergency = true;
    running = false;
    spindle = false;
    status = "Emergency Stop";
    return;
  }

  if (emergency) return;

  // Mode selection
  if (mouseY > 78 && mouseY < 106) {
    if (mouseX < 140) machineMode = "CNC";
    if (mouseX > 150 && mouseX < 300)
      machineMode = "3D PRINTER";
  }

  // Refresh
  if (mouseX > 225 && mouseX < 340 &&
      mouseY > 185 && mouseY < 215) {
    refreshPorts();
  }

  // Connect
  if (mouseX > 35 && mouseX < 180 &&
      mouseY > 220 && mouseY < 247) {
    if (connected) {
      if (serial != null) serial.stop();
      serial = null;
      connected = false;
      status = "Disconnected";
    } else {
      connectMachine();
    }
  }

  // Next port
  if (mouseX > 190 && mouseX < 340 &&
      mouseY > 220 && mouseY < 247) {
    if (ports.length > 0) {
      int index = 0;

      for (int i = 0; i < ports.length; i++) {
        if (ports[i].equals(selectedPort)) index = i;
      }

      selectedPort = ports[(index+1)%ports.length];
    }
  }

  // Jog distance
  if (mouseY > 340 && mouseY < 370 &&
      mouseX >= 35 && mouseX < 335) {
    int index = (mouseX-35)/75;
    if (index >= 0 && index < 4) {
      jogStep = float(new String[]{"0.1","1","10","100"}[index]);
    }
  }

  // Jog buttons
  if (mouseY > 395 && mouseY < 540) {

    if (inside(125,395,65,45)) y += jogStep;
    if (inside(55,445,65,45)) x -= jogStep;
    if (inside(195,445,65,45)) x += jogStep;
    if (inside(125,495,65,45)) y -= jogStep;
    if (inside(270,395,65,45)) z += jogStep;
    if (inside(270,445,65,45)) z -= jogStep;

    if (inside(125,445,65,45)) {
      x = 0;
      y = 0;
      z = 0;
    }
  }

  // G-code
  if (mouseY > 590 && mouseY < 620) {
    if (mouseX > 800 && mouseX < 880) {
      commands = split(gcode, '\n');
      commandIndex = 0;
      running = true;
    }

    if (mouseX > 890 && mouseX < 970) {
      running = false;
    }

    if (mouseX > 980 && mouseX < 1060) {
      commandIndex = 0;
      running = false;
    }
  }
}

// =====================================
// HELPERS
// =====================================

boolean inside(int px, int py, int w, int h) {
  return mouseX >= px && mouseX <= px+w &&
         mouseY >= py && mouseY <= py+h;
}

void connectMachine() {
  if (selectedPort.equals("")) {
    status = "No serial port available";
    return;
  }

  try {
    serial = new Serial(this, selectedPort, 115200);
    connected = true;
    status = "Connected";
  }
  catch(Exception e) {
    status = "Connection failed";
    connected = false;
  }
}
