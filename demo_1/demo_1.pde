
import processing.serial.*;
import java.util.concurrent.ConcurrentLinkedQueue;

// =====================================
// OpenCNC - Processing 4 Prototype v0.2
// =====================================
//
// Every button is a Button object. The same object draws the button and
// detects clicks on it, so the click area always matches what you see.
//
// Without a serial connection the sketch runs in SIMULATION mode: nothing
// is sent anywhere, but jogging and G-code programs still move the virtual
// tool, so the whole UI can be tested without hardware.
//
// Keyboard: arrow keys jog X/Y, Page Up / Page Down jog Z.
//           Click the console box to type G-code, Enter sends it.

// ---------- Serial ----------
Serial serial;
String[] ports = new String[0];
String selectedPort = "";
final int BAUD_RATE = 115200;
boolean connected = false;
int pendingOk = 0;                 // lines sent that the machine has not answered "ok" to yet
int lastSendTime = 0;
int lastPortCheck = 0;
final int OK_TIMEOUT = 10000;      // ms to wait for "ok" before a program is paused
ConcurrentLinkedQueue<String> incoming = new ConcurrentLinkedQueue<String>();

// ---------- Machine ----------
String machineMode = "CNC";        // "CNC" or "3D PRINTER"
String status = "Disconnected (simulation)";
MachineState m = new MachineState();
boolean emergency = false;

float[] jogSteps = {0.1, 1, 10, 100};
float jogStep = 1;
int[] jogFeeds = {100, 250, 500, 1000, 2000, 3000, 5000};   // mm/min
int jogFeedIndex = 3;

Button heldJog = null;             // jog button held down for continuous jogging
int heldSince = 0;
int lastJogRepeat = 0;
final int JOG_REPEAT_DELAY = 400;
final int JOG_REPEAT_INTERVAL = 150;

// ---------- G-code program ----------
String gcodeName = "demo.gcode";
String[] commands = {
  "G21 ; millimeters",
  "G90 ; absolute positioning",
  "G0 X10 Y10",
  "M3 S10000",
  "G1 Z-2 F100",
  "G1 X40 Y10 F300",
  "G1 X40 Y30",
  "G1 X10 Y30",
  "G1 X10 Y10",
  "G0 Z10",
  "M5",
  "G0 X0 Y0"
};
int commandIndex = 0;              // next line to send
int currentLine = -1;              // line being executed (highlighted)
boolean running = false;
boolean paused = false;
final int SIM_LINE_TIME = 300;     // ms per line in simulation mode
ArrayList<float[]> toolpath = new ArrayList<float[]>();   // {x1, y1, x2, y2, rapid ? 1 : 0}
File fileToLoad = null;            // set by the file dialog thread, loaded in draw()

// ---------- Console ----------
ArrayList<String> consoleLog = new ArrayList<String>();
String consoleInput = "";
boolean consoleFocused = false;
final int INPUT_X = 755, INPUT_Y = 595, INPUT_W = 245, INPUT_H = 28;

// ---------- Visualization ----------
float vizScale = 4;                // pixels per mm
final int VIZ_X = 395, VIZ_Y = 160, VIZ_W = 590, VIZ_H = 270;

// ---------- UI colors ----------
color bg      = color(28, 32, 39);
color panel   = color(43, 49, 59);
color btnGray = color(62, 70, 84);
color blue    = color(45, 120, 210);
color green   = color(40, 160, 100);
color red     = color(190, 55, 55);
color orange  = color(210, 130, 40);
color teal    = color(40, 140, 150);

boolean hoverButton = false;

// ---------- Buttons ----------
Button btnCnc, btnPrinter;
Button btnRefresh, btnConnect, btnNextPort;
Button[] btnSteps = new Button[4];
Button btnYPlus, btnYMinus, btnXPlus, btnXMinus, btnZPlus, btnZMinus;
Button btnHome, btnZero;
Button btnFeedMinus, btnFeedPlus;
Button btnLoad, btnRun, btnPause, btnStop;
Button btnSend;
Button btnSpindle, btnMotorsOff;
Button btnEstop;

void setup() {
  size(1100, 750);
  textFont(createFont("SansSerif", 14));   // always available, unlike "Arial" on Linux

  createButtons();
  refreshPorts();
  buildToolpath();
  fitView();
  addLog("OpenCNC ready - simulation mode until connected");
}

void draw() {
  if (fileToLoad != null) {
    File f = fileToLoad;
    fileToLoad = null;
    loadProgram(f);
  }

  processIncoming();
  checkConnection();
  updateHeldJog();
  updateProgram();

  background(bg);
  hoverButton = false;

  drawHeader();
  drawConnection();
  drawMachineControl();
  drawVisualization();
  drawProgram();
  drawConsole();
  drawFooter();

  cursor(hoverButton ? HAND : ARROW);
}

void createButtons() {
  btnCnc     = new Button(20, 78, 120, 28, "CNC MODE");
  btnPrinter = new Button(150, 78, 150, 28, "3D PRINTER");

  btnRefresh  = new Button(225, 185, 115, 30, "Refresh");
  btnConnect  = new Button(35, 222, 145, 27, "Connect");
  btnNextPort = new Button(190, 222, 150, 27, "Select Next Port");

  for (int i = 0; i < jogSteps.length; i++) {
    btnSteps[i] = new Button(35 + i*76, 335, 68, 28, fmtShort(jogSteps[i]));
  }

  btnYPlus  = new Button(125, 375, 65, 42, "Y+");
  btnXMinus = new Button(55, 422, 65, 42, "X-");
  btnHome   = new Button(125, 422, 65, 42, "HOME");
  btnXPlus  = new Button(195, 422, 65, 42, "X+");
  btnYMinus = new Button(125, 469, 65, 42, "Y-");
  btnZPlus  = new Button(270, 375, 65, 42, "Z+");
  btnZMinus = new Button(270, 422, 65, 42, "Z-");
  btnZero   = new Button(270, 469, 65, 42, "ZERO");

  btnFeedMinus = new Button(150, 525, 36, 26, "-");
  btnFeedPlus  = new Button(299, 525, 36, 26, "+");

  btnLoad  = new Button(395, 595, 74, 28, "Load");
  btnRun   = new Button(473, 595, 74, 28, "Run");
  btnPause = new Button(551, 595, 74, 28, "Pause");
  btnStop  = new Button(629, 595, 74, 28, "Stop");

  btnSend = new Button(1005, 595, 60, 28, "Send");

  btnSpindle   = new Button(20, 655, 160, 40, "SPINDLE ON");
  btnMotorsOff = new Button(190, 655, 140, 40, "MOTORS OFF");
  btnEstop     = new Button(880, 655, 200, 45, "EMERGENCY STOP");
  btnEstop.textSz = 14;
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

  noStroke();
  fill(panel);
  rect(0, 70, width, 45);

  btnCnc.show(machineMode.equals("CNC") ? blue : btnGray, idle());
  btnPrinter.show(machineMode.equals("3D PRINTER") ? blue : btnGray, idle());

  fill(emergency ? red : (connected ? green : orange));
  ellipse(1030, 92, 10, 10);

  fill(255);
  textSize(13);
  textAlign(RIGHT);
  text(status, 1015, 97);
  textAlign(LEFT);
}

// =====================================
// CONNECTION
// =====================================

void drawConnection() {
  drawPanel(20, 130, 340, 125, "CONNECTION");

  fill(200);
  textSize(13);
  text("Serial Port (" + ports.length + " found, " + BAUD_RATE + " baud):", 35, 175);

  noStroke();
  fill(connected ? color(215, 245, 225) : color(255));
  rect(35, 185, 180, 30, 4);

  fill(30);
  text(selectedPort.equals("") ? "No port found" : fitText(selectedPort, 160), 45, 205);

  btnRefresh.show(blue, idle());

  btnConnect.label = connected ? "Disconnect" : "Connect";
  btnConnect.show(connected ? red : green,
    !running && (connected || !selectedPort.equals("")));

  btnNextPort.show(btnGray, idle() && !connected && ports.length > 1);
}

// =====================================
// MACHINE CONTROL
// =====================================

void drawMachineControl() {
  drawPanel(20, 275, 340, 360, "MANUAL MACHINE CONTROL");

  fill(200);
  textSize(13);
  text("Jog Distance (mm):", 35, 325);

  for (int i = 0; i < btnSteps.length; i++) {
    btnSteps[i].show(jogStep == jogSteps[i] ? blue : btnGray, !emergency);
  }

  boolean canJog = idle();
  btnYPlus.show(btnGray, canJog);
  btnXMinus.show(btnGray, canJog);
  btnHome.show(blue, canJog);
  btnXPlus.show(btnGray, canJog);
  btnYMinus.show(btnGray, canJog);
  btnZPlus.show(btnGray, canJog);
  btnZMinus.show(btnGray, canJog);
  btnZero.show(teal, canJog);

  fill(200);
  textSize(13);
  text("Jog Feed:", 35, 543);
  btnFeedMinus.show(btnGray, !emergency && jogFeedIndex > 0);
  btnFeedPlus.show(btnGray, !emergency && jogFeedIndex < jogFeeds.length - 1);
  fill(255);
  textAlign(CENTER);
  text(jogFeeds[jogFeedIndex] + " mm/min", 242, 543);
  textAlign(LEFT);

  fill(200);
  text("Position (mm)", 35, 580);

  fill(255);
  textSize(15);
  text("X " + fmt(m.x, 2), 35, 607);
  text("Y " + fmt(m.y, 2), 140, 607);
  text("Z " + fmt(m.z, 2), 245, 607);
}

// =====================================
// VISUALIZATION
// =====================================

void drawVisualization() {
  drawPanel(380, 130, 700, 330, "MACHINE VISUALIZATION");

  if (!connected) {
    fill(orange);
    textSize(11);
    textAlign(RIGHT);
    text("SIMULATION MODE", VIZ_X + VIZ_W, 153);
    textAlign(LEFT);
  }

  float cx = VIZ_X + VIZ_W/2.0;
  float cy = VIZ_Y + VIZ_H/2.0;

  noStroke();
  fill(32, 37, 45);
  rect(VIZ_X, VIZ_Y, VIZ_W, VIZ_H, 4);

  clip(VIZ_X, VIZ_Y, VIZ_W, VIZ_H);

  // Grid: pick a spacing that stays readable at the current zoom
  float gridMm = 10;
  while (gridMm * vizScale < 20) gridMm *= 5;
  while (gridMm * vizScale > 150) gridMm /= 5;
  float g = gridMm * vizScale;

  stroke(52, 59, 70);
  strokeWeight(1);
  int nx = ceil(VIZ_W / 2.0 / g);
  int ny = ceil(VIZ_H / 2.0 / g);
  for (int i = -nx; i <= nx; i++) line(cx + i*g, VIZ_Y, cx + i*g, VIZ_Y + VIZ_H);
  for (int i = -ny; i <= ny; i++) line(VIZ_X, cy + i*g, VIZ_X + VIZ_W, cy + i*g);

  // Axes
  stroke(255, 80, 80);
  line(cx, cy, cx + 60, cy);
  stroke(80, 255, 120);
  line(cx, cy, cx, cy - 60);

  // Toolpath preview (orange = rapid G0, cyan = cutting G1/G2/G3)
  for (float[] s : toolpath) {
    if (s[4] == 1) stroke(210, 130, 40, 150);
    else stroke(80, 200, 255);
    line(cx + s[0]*vizScale, cy - s[1]*vizScale,
         cx + s[2]*vizScale, cy - s[3]*vizScale);
  }

  // Tool position
  float px = cx + m.x * vizScale;
  float py = cy - m.y * vizScale;

  // Direction arrow for the last move
  float len = dist(0, 0, m.dirX, m.dirY);
  if (millis() - m.movedAt < 600 && len > 0) {
    stroke(255, 220, 0);
    strokeWeight(2);
    pushMatrix();
    translate(px, py);
    rotate(atan2(-m.dirY, m.dirX));
    line(-45, 0, -12, 0);
    line(-12, 0, -20, -5);
    line(-12, 0, -20, 5);
    popMatrix();
    strokeWeight(1);
  }

  stroke(255, 120);
  line(px - 12, py, px + 12, py);
  line(px, py - 12, px, py + 12);
  noStroke();
  fill(m.spindle ? orange : blue);
  ellipse(px, py, 14, 14);

  noClip();

  // Z height bar
  int zx = 1000, zy = 165, zw = 50, zh = 265;
  noStroke();
  fill(32, 37, 45);
  rect(zx, zy, zw, zh, 4);
  float zRange = max(50, abs(m.z));
  float zZero = map(0, -zRange, zRange, zy + zh - 10, zy + 10);
  float zPos  = map(m.z, -zRange, zRange, zy + zh - 10, zy + 10);
  stroke(90);
  line(zx + zw/2, zy + 10, zx + zw/2, zy + zh - 10);
  stroke(255, 80, 80);
  line(zx + 8, zZero, zx + zw - 8, zZero);
  noStroke();
  fill(blue);
  rect(zx + 10, zPos - 4, zw - 20, 8, 2);

  fill(180);
  textSize(12);
  textAlign(CENTER);
  text("Z", zx + zw/2, 450);
  textAlign(LEFT);

  // Info line
  fill(200);
  if (machineMode.equals("CNC")) {
    text("Spindle: " + (m.spindle ? "ON  (" + m.spindleSpeed + " RPM)" : "OFF"), 395, 450);
  } else {
    text("Part fan: " + (m.spindle ? "ON" : "OFF"), 395, 450);
  }
  fill(140);
  textAlign(RIGHT);
  text("Grid " + fmtShort(gridMm) + " mm  |  scroll to zoom", VIZ_X + VIZ_W, 450);
  textAlign(LEFT);
}

// =====================================
// G-CODE PROGRAM
// =====================================

void drawProgram() {
  drawPanel(380, 480, 340, 155, "G-CODE PROGRAM");

  fill(150);
  textSize(11);
  textAlign(RIGHT);
  text(fitText(gcodeName, 110) + "  " + commandIndex + "/" + commands.length, 705, 505);
  textAlign(LEFT);

  int visible = 4;
  int focus = currentLine >= 0 ? currentLine : commandIndex;
  int start = constrain(focus - 1, 0, max(0, commands.length - visible));

  textSize(12);
  for (int i = 0; i < visible && start + i < commands.length; i++) {
    int n = start + i;
    float ly = 522 + i*17;

    if (n == currentLine) {
      noStroke();
      fill(45, 85, 65);
      rect(391, ly - 13, 318, 17, 3);
      fill(110, 230, 160);
    } else if (n < commandIndex) {
      fill(120);
    } else {
      fill(210);
    }
    text(nf(n + 1, 3) + "   " + fitText(commands[n], 260), 395, ly);
  }

  // Progress bar
  float progress = commands.length == 0 ? 0 : commandIndex / (float) commands.length;
  noStroke();
  fill(30, 34, 42);
  rect(395, 582, 310, 6, 3);
  fill(green);
  rect(395, 582, 310 * progress, 6, 3);

  btnLoad.show(btnGray, idle());

  btnRun.label = paused ? "Resume" : (running ? "Running" : "Run");
  btnRun.show(green, !emergency && commands.length > 0 && (!running || paused));

  btnPause.show(orange, running && !paused);
  btnStop.show(red, running);
}

// =====================================
// CONSOLE
// =====================================

void drawConsole() {
  drawPanel(740, 480, 340, 155, "CONSOLE");

  textSize(11);
  int visible = 4;
  int start = max(0, consoleLog.size() - visible);
  for (int i = start; i < consoleLog.size(); i++) {
    String s = consoleLog.get(i);
    if (s.startsWith("<")) fill(120, 210, 150);
    else if (s.startsWith("!")) fill(240, 110, 110);
    else fill(200);
    text(fitText(s, 310), 755, 522 + (i - start) * 17);
  }

  // Input box
  stroke(consoleFocused ? blue : color(80));
  strokeWeight(consoleFocused ? 2 : 1);
  fill(consoleFocused ? color(255) : color(225));
  rect(INPUT_X, INPUT_Y, INPUT_W, INPUT_H, 4);
  noStroke();
  strokeWeight(1);

  textSize(12);
  if (consoleInput.length() == 0 && !consoleFocused) {
    fill(130);
    text("Click to type G-code...", INPUT_X + 8, INPUT_Y + 19);
  } else {
    fill(30);
    boolean caret = consoleFocused && (millis() / 500) % 2 == 0;
    text(fitTail(consoleInput + (caret ? "|" : ""), INPUT_W - 16), INPUT_X + 8, INPUT_Y + 19);
  }

  btnSend.show(blue, idle() && consoleInput.trim().length() > 0);
}

// =====================================
// FOOTER
// =====================================

void drawFooter() {
  btnSpindle.label = (machineMode.equals("CNC") ? "SPINDLE " : "FAN ") + (m.spindle ? "OFF" : "ON");
  btnSpindle.show(m.spindle ? orange : btnGray, idle());
  btnMotorsOff.show(btnGray, idle());

  btnEstop.label = emergency ? "RESET E-STOP" : "EMERGENCY STOP";
  btnEstop.show(emergency ? orange : red, true);

  String state = emergency ? "EMERGENCY STOP ACTIVE"
    : running ? (paused ? "PROGRAM PAUSED" : "PROGRAM RUNNING")
    : "SYSTEM READY";
  fill(emergency ? red : (running ? green : color(130)));
  textSize(13);
  textAlign(RIGHT);
  text(state, 865, 683);
  textAlign(LEFT);

  fill(110);
  textSize(12);
  text("OpenCNC v0.2 | Processing 4 | Prototype", 20, 730);
}

// =====================================
// PANEL / BUTTON
// =====================================

void drawPanel(int px, int py, int w, int h, String title) {
  noStroke();
  fill(panel);
  rect(px, py, w, h, 8);

  fill(255);
  textSize(15);
  text(title, px + 15, py + 25);
}

class Button {
  int bx, by, bw, bh;
  String label;
  int textSz = 12;
  boolean enabled = true;

  Button(int bx, int by, int bw, int bh, String label) {
    this.bx = bx;
    this.by = by;
    this.bw = bw;
    this.bh = bh;
    this.label = label;
  }

  boolean over() {
    return mouseX >= bx && mouseX <= bx + bw &&
           mouseY >= by && mouseY <= by + bh;
  }

  // Uses the enabled state from the last frame it was drawn
  boolean clicked() {
    return enabled && over();
  }

  void show(color c, boolean isEnabled) {
    enabled = isEnabled;

    color fillColor = c;
    if (!enabled) {
      fillColor = lerpColor(c, bg, 0.55);
    } else if (over()) {
      fillColor = lerpColor(c, color(255), mousePressed ? 0.25 : 0.12);
      hoverButton = true;
    }

    noStroke();
    fill(fillColor);
    rect(bx, by, bw, bh, 5);

    fill(enabled ? 255 : 140);
    textAlign(CENTER, CENTER);
    textSize(textSz);
    text(label, bx + bw/2.0, by + bh/2.0);
    textAlign(LEFT, BASELINE);
  }
}

// =====================================
// MOUSE / KEYBOARD
// =====================================

void mousePressed() {
  consoleFocused = mouseX >= INPUT_X && mouseX <= INPUT_X + INPUT_W &&
                   mouseY >= INPUT_Y && mouseY <= INPUT_Y + INPUT_H;

  if (btnEstop.clicked()) {
    if (emergency) resetEmergency();
    else triggerEmergency();
    return;
  }

  // Mode
  if (btnCnc.clicked()) setMode("CNC");
  if (btnPrinter.clicked()) setMode("3D PRINTER");

  // Connection
  if (btnRefresh.clicked()) {
    refreshPorts();
    addLog("Found " + ports.length + " serial port(s)");
  }
  if (btnConnect.clicked()) {
    if (connected) disconnect("Disconnected");
    else connectMachine();
  }
  if (btnNextPort.clicked()) selectNextPort();

  // Jog settings
  for (int i = 0; i < btnSteps.length; i++) {
    if (btnSteps[i].clicked()) jogStep = jogSteps[i];
  }
  if (btnFeedMinus.clicked()) jogFeedIndex--;
  if (btnFeedPlus.clicked()) jogFeedIndex++;

  // Jog buttons (hold for continuous jogging)
  Button[] jogButtons = {btnXPlus, btnXMinus, btnYPlus, btnYMinus, btnZPlus, btnZMinus};
  for (Button b : jogButtons) {
    if (b.clicked()) {
      jogWithButton(b);
      heldJog = b;
      heldSince = millis();
      lastJogRepeat = millis();
    }
  }
  if (btnHome.clicked()) sendCommand("G28");
  if (btnZero.clicked()) sendCommand("G92 X0 Y0 Z0");

  // Program
  if (btnLoad.clicked()) selectInput("Select a G-code file", "fileSelected");
  if (btnRun.clicked()) runProgram();
  if (btnPause.clicked()) pauseProgram();
  if (btnStop.clicked()) stopProgram();

  // Console
  if (btnSend.clicked()) submitConsole();

  // Machine functions
  if (btnSpindle.clicked()) toggleSpindle();
  if (btnMotorsOff.clicked()) sendCommand("M18");
}

void mouseReleased() {
  heldJog = null;
}

void mouseWheel(MouseEvent event) {
  if (mouseX < VIZ_X || mouseX > VIZ_X + VIZ_W ||
      mouseY < VIZ_Y || mouseY > VIZ_Y + VIZ_H) return;
  float factor = event.getCount() > 0 ? 0.9 : 1.1;
  vizScale = constrain(vizScale * factor, 0.1, 50);
}

void keyPressed() {
  // ESC would close the sketch - don't let that happen by accident
  if (key == ESC) {
    key = 0;
    consoleFocused = false;
    return;
  }

  if (consoleFocused) {
    if (key == ENTER || key == RETURN) {
      submitConsole();
    } else if (key == BACKSPACE) {
      if (consoleInput.length() > 0) {
        consoleInput = consoleInput.substring(0, consoleInput.length() - 1);
      }
    } else if (key != CODED && key >= 32 && key < 127 && consoleInput.length() < 60) {
      consoleInput += key;
    }
    return;
  }

  if (!idle() || key != CODED) return;

  if (keyCode == UP)    jog(0, jogStep, 0);
  if (keyCode == DOWN)  jog(0, -jogStep, 0);
  if (keyCode == LEFT)  jog(-jogStep, 0, 0);
  if (keyCode == RIGHT) jog(jogStep, 0, 0);
  if (keyCode == java.awt.event.KeyEvent.VK_PAGE_UP)   jog(0, 0, jogStep);
  if (keyCode == java.awt.event.KeyEvent.VK_PAGE_DOWN) jog(0, 0, -jogStep);
}

// =====================================
// MACHINE FUNCTIONS
// =====================================

// True when manual commands are allowed
boolean idle() {
  return !emergency && !running;
}

String idleStatus() {
  return connected ? "Connected" : "Disconnected (simulation)";
}

void setMode(String mode) {
  if (machineMode.equals(mode)) return;
  if (m.spindle) toggleSpindle();   // turn off spindle / fan of the old mode
  machineMode = mode;
  addLog("Mode: " + mode);
}

void jogWithButton(Button b) {
  if (b == btnXPlus)  jog(jogStep, 0, 0);
  if (b == btnXMinus) jog(-jogStep, 0, 0);
  if (b == btnYPlus)  jog(0, jogStep, 0);
  if (b == btnYMinus) jog(0, -jogStep, 0);
  if (b == btnZPlus)  jog(0, 0, jogStep);
  if (b == btnZMinus) jog(0, 0, -jogStep);
}

void jog(float dx, float dy, float dz) {
  if (!idle()) return;

  String move = "G91 G1";
  if (dx != 0) move += " X" + fmt(dx, 3);
  if (dy != 0) move += " Y" + fmt(dy, 3);
  if (dz != 0) move += " Z" + fmt(dz, 3);
  move += " F" + jogFeeds[jogFeedIndex];

  sendCommand(move);
  sendCommand("G90");
}

void updateHeldJog() {
  if (heldJog == null) return;

  if (!mousePressed || !heldJog.over() || !idle()) {
    heldJog = null;
    return;
  }

  int now = millis();
  if (now - heldSince < JOG_REPEAT_DELAY) return;
  if (now - lastJogRepeat < JOG_REPEAT_INTERVAL) return;
  if (connected && pendingOk > 0) return;   // wait until the machine accepted the last jog

  jogWithButton(heldJog);
  lastJogRepeat = now;
}

void toggleSpindle() {
  boolean cnc = machineMode.equals("CNC");
  if (m.spindle) sendCommand(cnc ? "M5" : "M107");
  else sendCommand(cnc ? "M3 S" + m.spindleSpeed : "M106 S255");
}

void triggerEmergency() {
  emergency = true;
  running = false;
  paused = false;
  commandIndex = 0;
  currentLine = -1;
  heldJog = null;
  m.spindle = false;

  if (connected && serial != null) {
    try {
      serial.write("M112\n");
    }
    catch (Exception e) {
    }
    addLog("! EMERGENCY STOP - M112 sent");
  } else {
    addLog("! EMERGENCY STOP (simulation)");
  }
  status = "EMERGENCY STOP";
}

void resetEmergency() {
  emergency = false;
  pendingOk = 0;
  status = idleStatus();
  addLog("E-stop reset - home the machine before running");
}

void submitConsole() {
  if (!idle()) return;
  String c = consoleInput.trim();
  if (c.length() == 0) return;
  sendCommand(c);
  consoleInput = "";
}

// =====================================
// G-CODE PROGRAM CONTROL
// =====================================

void runProgram() {
  if (commands.length == 0) return;

  if (paused) {
    paused = false;
    pendingOk = 0;
    lastSendTime = millis();
    status = "Running";
    addLog("Program resumed");
    return;
  }

  if (commandIndex >= commands.length) commandIndex = 0;
  running = true;
  paused = false;
  pendingOk = 0;
  currentLine = -1;
  lastSendTime = 0;
  status = "Running";
  addLog("Program started: " + gcodeName);
}

// Stops streaming new lines. Moves already buffered in the
// machine will still finish.
void pauseProgram() {
  paused = true;
  status = "Paused";
  addLog("Program paused");
}

void stopProgram() {
  running = false;
  paused = false;
  commandIndex = 0;
  currentLine = -1;
  status = idleStatus();
  addLog("Program stopped");
  if (m.spindle) toggleSpindle();
}

void updateProgram() {
  if (!running || paused || emergency) return;

  if (connected) {
    // Send the next line only after the machine answered "ok"
    if (pendingOk > 0) {
      if (millis() - lastSendTime > OK_TIMEOUT) {
        paused = true;
        status = "No response from machine";
        addLog("! No 'ok' for " + OK_TIMEOUT/1000 + "s - program paused");
      }
      return;
    }
  } else if (millis() - lastSendTime < SIM_LINE_TIME) {
    return;
  }

  // Skip empty lines and comments
  while (commandIndex < commands.length && cleanLine(commands[commandIndex]).length() == 0) {
    commandIndex++;
  }

  if (commandIndex >= commands.length) {
    running = false;
    currentLine = -1;
    status = idleStatus();
    addLog("Program finished");
    return;
  }

  currentLine = commandIndex;
  sendCommand(commands[commandIndex]);
  commandIndex++;
}

void fileSelected(File selection) {
  if (selection != null) fileToLoad = selection;
}

void loadProgram(File f) {
  String[] lines = loadStrings(f.getAbsolutePath());
  if (lines == null) {
    addLog("! Could not read " + f.getName());
    return;
  }

  commands = lines;
  gcodeName = f.getName();
  commandIndex = 0;
  currentLine = -1;
  buildToolpath();
  fitView();
  addLog("Loaded " + gcodeName + " (" + lines.length + " lines)");
}

// Run the program through a separate MachineState to get the XY path
void buildToolpath() {
  toolpath.clear();
  MachineState s = new MachineState();
  for (String line : commands) {
    float ox = s.x;
    float oy = s.y;
    s.apply(line);
    if (s.x != ox || s.y != oy) {
      toolpath.add(new float[] {ox, oy, s.x, s.y, s.motion == 0 ? 1 : 0});
    }
  }
}

// Zoom so the whole toolpath fits in the view
void fitView() {
  float maxX = 1;
  float maxY = 1;
  for (float[] s : toolpath) {
    maxX = max(maxX, abs(s[0]), abs(s[2]));
    maxY = max(maxY, abs(s[1]), abs(s[3]));
  }
  vizScale = constrain(min((VIZ_W/2 - 20) / maxX, (VIZ_H/2 - 15) / maxY), 0.1, 50);
}

// =====================================
// MACHINE STATE / G-CODE PARSER
// =====================================

class MachineState {
  float x = 0, y = 0, z = 0;
  boolean absolute = true;
  int motion = 0;               // last G0/G1/G2/G3
  boolean spindle = false;      // spindle (CNC) or part fan (3D printer)
  int spindleSpeed = 10000;
  float dirX = 0, dirY = 0;     // direction of the last XY move
  int movedAt = -10000;

  // Update the state from one line of G-code
  void apply(String line) {
    String[][] words = matchAll(cleanLine(line), "([A-Z])\\s*([-+]?[0-9]*\\.?[0-9]+)");
    if (words == null) return;

    float nx = Float.NaN, ny = Float.NaN, nz = Float.NaN;
    float s = -1;
    boolean setPos = false, home = false, spindleStart = false;

    for (int i = 0; i < words.length; i++) {
      char letter = words[i][1].charAt(0);
      float v = parseFloat(words[i][2]);
      int code = round(v);

      switch (letter) {
      case 'G':
        if (code >= 0 && code <= 3) motion = code;
        else if (code == 90) absolute = true;
        else if (code == 91) absolute = false;
        else if (code == 92) setPos = true;
        else if (code == 28) home = true;
        break;
      case 'M':
        if (code == 3 || code == 4) {
          spindle = true;
          spindleStart = true;
        } else if (code == 106) {
          spindle = true;
        } else if (code == 5 || code == 107) {
          spindle = false;
        }
        break;
      case 'S':
        s = v;
        break;
      case 'X':
        nx = v;
        break;
      case 'Y':
        ny = v;
        break;
      case 'Z':
        nz = v;
        break;
      }
    }

    if (spindleStart && s >= 0) spindleSpeed = round(s);

    if (home) {   // G28: home the given axes, or all of them
      boolean all = Float.isNaN(nx) && Float.isNaN(ny) && Float.isNaN(nz);
      if (all || !Float.isNaN(nx)) x = 0;
      if (all || !Float.isNaN(ny)) y = 0;
      if (all || !Float.isNaN(nz)) z = 0;
      return;
    }

    if (setPos) { // G92: set current position
      if (!Float.isNaN(nx)) x = nx;
      if (!Float.isNaN(ny)) y = ny;
      if (!Float.isNaN(nz)) z = nz;
      return;
    }

    float ox = x, oy = y;
    if (!Float.isNaN(nx)) x = absolute ? nx : x + nx;
    if (!Float.isNaN(ny)) y = absolute ? ny : y + ny;
    if (!Float.isNaN(nz)) z = absolute ? nz : z + nz;

    if (x != ox || y != oy) {
      dirX = x - ox;
      dirY = y - oy;
      movedAt = millis();
    }
  }
}

// Remove comments, trim and upper-case a G-code line
String cleanLine(String line) {
  if (line == null) return "";
  int semi = line.indexOf(';');
  if (semi >= 0) line = line.substring(0, semi);
  line = line.replaceAll("\\(.*?\\)", "");
  return line.trim().toUpperCase();
}

// =====================================
// SERIAL COMMUNICATION
// =====================================

void refreshPorts() {
  try {
    ports = Serial.list();
  }
  catch (Exception e) {
    ports = new String[0];
  }

  if (ports.length == 0) {
    selectedPort = "";
  } else if (!contains(ports, selectedPort)) {
    selectedPort = ports[0];
  }
}

void selectNextPort() {
  if (ports.length == 0) return;
  int index = 0;
  for (int i = 0; i < ports.length; i++) {
    if (ports[i].equals(selectedPort)) index = i;
  }
  selectedPort = ports[(index + 1) % ports.length];
}

void connectMachine() {
  if (selectedPort.equals("")) {
    status = "No serial port available";
    addLog("! No serial port available");
    return;
  }

  try {
    serial = new Serial(this, selectedPort, BAUD_RATE);
    serial.clear();
    serial.bufferUntil('\n');
    connected = true;
    pendingOk = 0;
    lastPortCheck = millis();
    status = "Connected";
    addLog("Connected to " + selectedPort + " @ " + BAUD_RATE);
  }
  catch (Exception e) {
    serial = null;
    connected = false;
    status = "Connection failed";
    addLog("! Could not open " + selectedPort);
  }
}

void disconnect(String reason) {
  if (running) {
    running = false;
    paused = false;
    currentLine = -1;
    addLog("! Program stopped");
  }
  if (serial != null) {
    try {
      serial.stop();
    }
    catch (Exception e) {
    }
  }
  serial = null;
  connected = false;
  pendingOk = 0;
  incoming.clear();
  status = reason;
  addLog(reason.equals("Disconnected") ? reason : "! " + reason);
}

// Communication-loss detection: the port disappeared (cable unplugged)
void checkConnection() {
  if (!connected || millis() - lastPortCheck < 2000) return;
  lastPortCheck = millis();

  String[] list;
  try {
    list = Serial.list();
  }
  catch (Exception e) {
    return;
  }
  ports = list;
  if (!contains(list, selectedPort)) disconnect("Connection lost");
}

// Send one line: over serial when connected, otherwise simulated
void sendCommand(String raw) {
  String cmd = cleanLine(raw);
  if (cmd.length() == 0) return;

  if (connected && serial != null) {
    try {
      serial.write(cmd + "\n");
      pendingOk++;
      addLog("> " + cmd);
    }
    catch (Exception e) {
      disconnect("Connection lost");
      return;
    }
  } else {
    addLog("[SIM] " + cmd);
  }

  lastSendTime = millis();
  m.apply(cmd);
}

// Runs on the serial thread: only queue the line, draw() handles it
void serialEvent(Serial p) {
  try {
    String line = p.readStringUntil('\n');
    if (line != null) {
      line = trim(line);
      if (line.length() > 0) incoming.add(line);
    }
  }
  catch (Exception e) {
  }
}

void processIncoming() {
  String line;
  while ((line = incoming.poll()) != null) {
    addLog("< " + line);
    String l = line.toLowerCase();

    if (l.startsWith("ok")) {
      if (pendingOk > 0) pendingOk--;
    } else if (l.startsWith("error") || l.startsWith("alarm")) {
      if (pendingOk > 0) pendingOk--;
      if (running && !paused) {
        paused = true;
        status = "Machine error - paused";
      }
    }
  }
}

// =====================================
// HELPERS
// =====================================

void addLog(String msg) {
  consoleLog.add(msg);
  println(msg);
  while (consoleLog.size() > 100) consoleLog.remove(0);
}

boolean contains(String[] list, String s) {
  for (String item : list) {
    if (item.equals(s)) return true;
  }
  return false;
}

// Locale-independent number formatting (always uses '.')
String fmt(float v, int decimals) {
  return String.format(java.util.Locale.US, "%." + decimals + "f", v);
}

String fmtShort(float v) {
  return v == (int) v ? str((int) v) : str(v);
}

// Cut text from the end so it fits in maxW pixels
String fitText(String s, float maxW) {
  if (textWidth(s) <= maxW) return s;
  while (s.length() > 0 && textWidth(s + "...") > maxW) {
    s = s.substring(0, s.length() - 1);
  }
  return s + "...";
}

// Cut text from the start so the end stays visible
String fitTail(String s, float maxW) {
  while (s.length() > 0 && textWidth(s) > maxW) s = s.substring(1);
  return s;
}
