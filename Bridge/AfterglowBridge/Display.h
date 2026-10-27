// Optional status screen for boards with a built-in 0.96" SSD1306 OLED (ideaspark, Heltec-style, etc.).
// Finds the display by probing the usual I2C pin pairs; boards without one just skip it.
#pragma once
#include <Arduino.h>
#include <Wire.h>
#include <U8x8lib.h>

namespace oled {

static U8X8 *u8 = nullptr;
static String shown[8];

struct Pins { int sda, scl, rst; };

static bool probe(int sda, int scl, uint8_t &addr) {
  Wire.end();
  if (!Wire.begin(sda, scl, 400000)) return false;
  for (uint8_t a : {0x3C, 0x3D}) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) { addr = a; return true; }
  }
  return false;
}

// Call once at boot.
static void begin() {
#if defined(CONFIG_IDF_TARGET_ESP32)
  // ideaspark / generic: 21/22. Some clones swap them. Heltec V2 / TTGO: 4/15 with reset on 16.
  const Pins tries[] = {{21, 22, -1}, {22, 21, -1}, {4, 15, 16}, {5, 4, -1}, {4, 5, -1}};
#elif defined(CONFIG_IDF_TARGET_ESP32S3)
  const Pins tries[] = {{17, 18, 21}, {8, 9, -1}, {41, 42, -1}, {5, 6, -1}};
#else
  const Pins tries[] = {{5, 6, -1}, {8, 9, -1}, {4, 5, -1}};
#endif
  for (const Pins &p : tries) {
    if (p.rst >= 0) {
      pinMode(p.rst, OUTPUT);
      digitalWrite(p.rst, LOW); delay(20); digitalWrite(p.rst, HIGH); delay(20);
    }
    uint8_t addr = 0;
    if (!probe(p.sda, p.scl, addr)) continue;
    u8 = new U8X8_SSD1306_128X64_NONAME_HW_I2C(U8X8_PIN_NONE, p.scl, p.sda);
    u8->setI2CAddress(addr << 1);
    u8->begin();
    u8->setPowerSave(0);
    u8->setFont(u8x8_font_chroma48medium8_r);
    u8->clearDisplay();
    Serial.printf("[afterglow] OLED found on SDA %d SCL %d (0x%02x)\n", p.sda, p.scl, addr);
    return;
  }
  Wire.end();
}

static bool present() { return u8 != nullptr; }

// Draws up to 8 lines of 16 characters, only redrawing lines that changed.
static void lines(const String l[8]) {
  if (!u8) return;
  for (int i = 0; i < 8; i++) {
    String s = l[i];
    if (s.length() > 16) s = s.substring(0, 16);
    while (s.length() < 16) s += ' ';
    if (s == shown[i]) continue;
    shown[i] = s;
    if (i == 0) u8->setInverseFont(1);
    u8->drawString(0, i, s.c_str());
    if (i == 0) u8->setInverseFont(0);
  }
}

}  // namespace oled
