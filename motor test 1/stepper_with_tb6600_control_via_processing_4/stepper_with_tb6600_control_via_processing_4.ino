
#define DIR_PIN 7
#define STEP_PIN 6

const float STEPS_PER_MM = 80.0;
// Example: 200-step motor, 1/16 microstepping,
// 20-tooth GT2 pulley, 2mm belt pitch:
// (200 * 16) / (20 * 2) = 80 steps/mm

const int STEP_DELAY = 500; // Microseconds

long currentSteps = 0;

void setup() {
  pinMode(DIR_PIN, OUTPUT);
  pinMode(STEP_PIN, OUTPUT);

  Serial.begin(115200);

  Serial.println("READY");
  sendPosition();
}

void loop() {
  if (Serial.available()) {
    String command = Serial.readStringUntil('\n');
    command.trim();

    if (command == "Z") {
      currentSteps = 0;
      sendPosition();
    }

    else if (command == "Q") {
      sendPosition();
    }

    else if (command.length() > 1) {
      char direction = command.charAt(0);
      float distance = command.substring(1).toFloat();

      if (distance <= 0) return;

      if (direction == 'F') {
        moveMotor(distance, true);
      }

      else if (direction == 'B') {
        moveMotor(distance, false);
      }
    }
  }
}

void moveMotor(float distance, bool forward) {

  long steps = round(distance * STEPS_PER_MM);

  digitalWrite(DIR_PIN, forward ? HIGH : LOW);
  delayMicroseconds(10);

  for (long i = 0; i < steps; i++) {
    digitalWrite(STEP_PIN, HIGH);
    delayMicroseconds(STEP_DELAY);

    digitalWrite(STEP_PIN, LOW);
    delayMicroseconds(STEP_DELAY);
  }

  if (forward) {
    currentSteps += steps;
  } else {
    currentSteps -= steps;
  }

  sendPosition();
}

void sendPosition() {
  float position = currentSteps / STEPS_PER_MM;

  Serial.print("POS:");
  Serial.println(position, 3);
}
