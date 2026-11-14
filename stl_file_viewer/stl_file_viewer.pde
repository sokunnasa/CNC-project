
import javax.swing.JFileChooser;
import javax.swing.filechooser.FileNameExtensionFilter;
import java.io.*;
import java.nio.*;
import java.nio.file.*;

ArrayList<PVector[]> triangles = new ArrayList<PVector[]>();

String statusText = "No STL loaded.";

float rotX = 0;
float rotY = 0;
float zoom = 1.0;

float modelScale = 1;
PVector modelCenter = new PVector();

int[] btnOpen  = {20, 50, 160, 35};
int[] btnClose = {195, 50, 130, 35};
int[] btnReset = {340, 50, 120, 35};

void setup() {
  size(900, 700, P3D);
  textSize(15);
}

void draw() {
  background(28, 32, 38);

  if (!triangles.isEmpty()) {
    pushMatrix();

    lights();
    directionalLight(255, 255, 255, -0.5, 0.8, -1);

    translate(width/2, height/2 + 30, 0);
    scale(zoom * modelScale);
    rotateX(rotX);
    rotateY(rotY);

    // Center model
    translate(-modelCenter.x, -modelCenter.y, -modelCenter.z);

    fill(180, 200, 220);
    stroke(35, 40, 50);
    strokeWeight(0.5);

    beginShape(TRIANGLES);

    for (PVector[] tri : triangles) {
      for (PVector v : tri) {
        vertex(v.x, v.y, v.z);
      }
    }

    endShape();

    popMatrix();
  }

  hint(DISABLE_DEPTH_TEST);

  fill(240);
  textAlign(LEFT, CENTER);
  text(statusText, 20, 25);

  drawButton(btnOpen, "Open STL File", color(45, 120, 210));
  drawButton(btnClose, "Close Model", color(190, 60, 60));
  drawButton(btnReset, "Reset View", color(70, 75, 85));

  fill(160);
  text("Mouse: Left drag = Rotate | Scroll = Zoom",
       20, height-20);

  hint(ENABLE_DEPTH_TEST);
}

void drawButton(int[] b, String label, color baseColor) {
  boolean hover = overButton(b);

  fill(hover ? lerpColor(baseColor, color(255), 0.2) : baseColor);
  noStroke();
  rect(b[0], b[1], b[2], b[3], 6);

  fill(255);
  textAlign(CENTER, CENTER);
  text(label, b[0]+b[2]/2, b[1]+b[3]/2);
}

boolean overButton(int[] b) {
  return mouseX >= b[0] && mouseX <= b[0]+b[2] &&
         mouseY >= b[1] && mouseY <= b[1]+b[3];
}

void mousePressed() {
  if (overButton(btnOpen)) {
    openFileDialog();
  } else if (overButton(btnClose)) {
    triangles.clear();
    statusText = "Model closed.";
  } else if (overButton(btnReset)) {
    rotX = 0;
    rotY = 0;
    zoom = 1;
  }
}

void openFileDialog() {
  JFileChooser chooser = new JFileChooser();

  FileNameExtensionFilter filter =
    new FileNameExtensionFilter("STL Files (*.stl)", "stl");

  chooser.setFileFilter(filter);

  int result = chooser.showOpenDialog(null);

  if (result == JFileChooser.APPROVE_OPTION) {
    File file = chooser.getSelectedFile();

    try {
      loadSTL(file);
      statusText = "Loaded: " + file.getName() +
                   " | Triangles: " + triangles.size();

      rotX = 0;
      rotY = 0;
      zoom = 1;

    } catch (Exception e) {
      triangles.clear();
      statusText = "STL Error: " + e.getMessage();
      e.printStackTrace();
    }
  }
}

// Detect binary or ASCII STL
void loadSTL(File file) throws Exception {
  byte[] data = Files.readAllBytes(file.toPath());

  triangles.clear();

  if (isBinarySTL(data)) {
    loadBinarySTL(data);
  } else {
    loadASCIISTL(data);
  }

  if (triangles.isEmpty()) {
    throw new Exception("No triangles found.");
  }

  centerAndScaleModel();
}

// Binary STL detection
boolean isBinarySTL(byte[] data) {
  if (data.length < 84) return false;

  ByteBuffer buffer = ByteBuffer.wrap(data)
    .order(ByteOrder.LITTLE_ENDIAN);

  long count = buffer.getInt(80) & 0xffffffffL;

  return 84L + count * 50L == data.length;
}

// Read binary STL
void loadBinarySTL(byte[] data) {
  ByteBuffer buffer = ByteBuffer.wrap(data)
    .order(ByteOrder.LITTLE_ENDIAN);

  buffer.position(84);

  long count = (data.length - 84) / 50;

  for (int i = 0; i < count; i++) {

    // Normal vector
    buffer.getFloat();
    buffer.getFloat();
    buffer.getFloat();

    PVector[] tri = new PVector[3];

    for (int j = 0; j < 3; j++) {
      float x = buffer.getFloat();
      float y = buffer.getFloat();
      float z = buffer.getFloat();

      tri[j] = new PVector(x, y, z);
    }

    buffer.getShort(); // Attribute byte count

    triangles.add(tri);
  }
}

// Read ASCII STL
void loadASCIISTL(byte[] data) throws Exception {
  String content = new String(data, "US-ASCII");

  String[] lines = splitTokens(content, "\r\n");

  ArrayList<PVector> vertices = new ArrayList<PVector>();

  for (String line : lines) {
    String s = trim(line);

    if (s.startsWith("vertex ")) {
      String[] parts = splitTokens(s, " ");

      if (parts.length >= 4) {
        float x = Float.parseFloat(parts[1]);
        float y = Float.parseFloat(parts[2]);
        float z = Float.parseFloat(parts[3]);

        vertices.add(new PVector(x, y, z));
      }
    }
  }

  for (int i = 0; i + 2 < vertices.size(); i += 3) {
    PVector[] tri = new PVector[3];

    tri[0] = vertices.get(i);
    tri[1] = vertices.get(i+1);
    tri[2] = vertices.get(i+2);

    triangles.add(tri);
  }
}

// Calculate model center and automatic viewing scale
void centerAndScaleModel() {
  PVector minV = new PVector(
    Float.MAX_VALUE, Float.MAX_VALUE, Float.MAX_VALUE);

  PVector maxV = new PVector(
    -Float.MAX_VALUE, -Float.MAX_VALUE, -Float.MAX_VALUE);

  for (PVector[] tri : triangles) {
    for (PVector v : tri) {
      minV.x = min(minV.x, v.x);
      minV.y = min(minV.y, v.y);
      minV.z = min(minV.z, v.z);

      maxV.x = max(maxV.x, v.x);
      maxV.y = max(maxV.y, v.y);
      maxV.z = max(maxV.z, v.z);
    }
  }

  modelCenter = PVector.add(minV, maxV).mult(0.5);

  float sx = maxV.x - minV.x;
  float sy = maxV.y - minV.y;
  float sz = maxV.z - minV.z;

  float largest = max(sx, max(sy, sz));

  modelScale = largest > 0 ? 300.0 / largest : 1;
}

void mouseDragged() {
  if (mouseY > 100 && !overButton(btnOpen) &&
      !overButton(btnClose) && !overButton(btnReset)) {

    rotY += (mouseX-pmouseX)*0.01;
    rotX -= (mouseY-pmouseY)*0.01;
  }
}

void mouseWheel(processing.event.MouseEvent event) {
  zoom -= event.getCount()*0.1;
  zoom = constrain(zoom, 0.05, 20);
}
