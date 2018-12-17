#define LED 13
#define COMMAND 2

void setup() {
  // Set up for Arduino Leonardo, which has separate Serial ports for USB and header pins.
  Serial.begin(19200); // USB serial
  Serial1.begin(19200);  // Pins 0 (Rx) and 1 (Tx)
  Serial.setTimeout(200); // milliseconds
  Serial1.setTimeout(200);

  // Use GPIO pin 2 as input for the Command line on the Atari SIO bus.
  pinMode(COMMAND, INPUT_PULLUP);
}

void loop() {
  byte buffer[5];
  int count;

  // Wait for Command line (LOW), and then read a 5-byte command frame.
  if (digitalRead(COMMAND) == LOW) {
    count = Serial1.readBytes(buffer, 5);
    if (count == 5) {
      parseCommand(buffer);
    }
  }
}

void parseCommand(byte buffer[5]) {
  byte device = buffer[0];
  unsigned int sector = (unsigned int)buffer[2] + 256 * (unsigned int)buffer[3];
  byte checksum = buffer[4];

  // Ignore devices other than D1-D8.
  if (device < 0x31 || device > 0x38) {
    return;
  }

  byte calculatedCheck = crc(buffer, 4);

  // Wait for command to be clear (HIGH)
  while (digitalRead(COMMAND) != HIGH) {
    delay(1); // milliseconds
  }
  // Add a delay just to be safe
  delay(1); // milliseconds

  // Verify checksum
  if (checksum != calculatedCheck) {
    Serial1.write('E');
    return;
  }

  // Handle status and read commands
  switch (buffer[1]) {
    case 'S':
      Serial1.write('A');
      sendStatusToAtari(device);
      break;

    case 'R':
      Serial1.write('A');
      sendSectorToAtari(device, sector);
      break;

    default:
      // Unhandled command: send negative acknowledge
      Serial1.write('N');
      break;
  }
}

void sendStatusToAtari(byte device) {
  // Request status from Mac
  byte buffer[7];
  buffer[0] = 'S';
  buffer[1] = device;
  sendToMac(buffer, 2);

  // Delay 1 ms
  delay(1);

  // Get the status reply
  if (receiveFromMac(buffer, 6) != 0) {
    // Bytes 1-4 are the status bytes to send to the Atari
    Serial1.write('C');
    Serial1.write(buffer + 1, 4);
    Serial1.write(crc(buffer + 1, 4));
  } else {
    // Error
    Serial1.write('E');
    sendDebugInfoToMac("Error sending status.");
  }
}

void sendSectorToAtari(byte device, unsigned int sector) {
  byte sectorData[128];
  
  // Request sector status from Mac
  byte buffer[64];
  buffer[0] = 'R';
  buffer[1] = device;
  buffer[2] = sector % 256;
  buffer[3] = sector / 256;
  buffer[4] = 0xFF;
  sendToMac(buffer, 5);

  // Delay 1 ms
  delay(1);

  // Wait for reply
  if (receiveReply() != 0x41) {
    // Error
    Serial1.write('E');
    sendDebugInfoToMac("Error getting sector status.");
    return;
  }

  // Request 4 chunks of 32 bytes each to create sector data
  for (byte offset = 0; offset < 128; offset += 32) {
    // Request sector status from Mac
    byte buffer[64];
    buffer[0] = 'R';
    buffer[1] = device;
    buffer[2] = sector % 256;
    buffer[3] = sector / 256;
    buffer[4] = offset;
    sendToMac(buffer, 5);

    if (receiveFromMac(buffer, 34)) {
      // Copy buffer into sectorData
      for (int i = 0; i < 32; ++i) {
        sectorData[offset + i] = buffer[i + 1];
      }
    } else {
      // Error
      sendDebugInfoToMac("Error getting sector.");
      Serial1.write('E');
      return;
    }
  }

  // Complete
  Serial1.write('C');
  Serial1.write(sectorData, 128);
  Serial1.write(crc(sectorData, 128));
}

byte crc(byte buffer[], int count) {
  unsigned int result = 0;
  for (int index = 0; index < count; ++index) {
    result += buffer[index];
    result = (result / 256) + (result % 256);
  }
  return result;
}

void sendToMac(byte buffer[], byte count) {
  byte checksum = crc(buffer, count);
  Serial.write(count);
  Serial.write(buffer, count);
  Serial.write(checksum);
}

void sendDebugInfoToMac(String s) {
  byte buffer[128];
  byte length = s.length();
  buffer[0] = 1; // debugInfo command
  s.toCharArray(buffer + 1, 127);
  sendToMac(buffer, length + 1);
}

byte receiveFromMac(byte outBuffer[], byte count) {
  int readCount = Serial.readBytes(outBuffer, count);
  if (readCount != (int)count) {
    return 0;
  }

  // First byte should equal the count - 2
  if (outBuffer[0] != count - 2) {
    return 0;
  }

  // Verify checksum
  byte checksum = crc(outBuffer + 1, count - 2);
  if (checksum != outBuffer[count - 1]) {
    return 0;
  }

  return 1; // success
}

byte receiveReply() {
  byte readBuffer[1];
  int readCount = Serial.readBytes(readBuffer, 1);
  if (readCount == 1) {
    return readBuffer[0];
  }
  sendDebugInfoToMac("No reply");
  return 0;
}
