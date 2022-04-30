#include <ESP8266WiFi.h>
#include <ESP8266HTTPClient.h>
#include <NTPClient.h>
#include <WiFiUdp.h>
#include <ArduinoJson.h>
#include "secrets.h"

int RED_LED = 4;

float ADC_REF_VOLTAGE = 3.3;

const char* endpoint = "https://fciwqxr7xl.execute-api.eu-west-1.amazonaws.com/prod";

WiFiUDP ntpUdp;
NTPClient timeClient(ntpUdp, "pool.ntp.org", 0);
HTTPClient httpClient;
WiFiClientSecure wifiClient;

void setup() {
  Serial.begin(115200);
  pinMode(RED_LED, OUTPUT);
  digitalWrite(RED_LED, HIGH);
  Serial.println("\nHELLO");
 
  Serial.println("Connecting to network...");
  pinMode(RED_LED, OUTPUT);

  WiFi.hostname("ESP");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  while (WiFi.status() != WL_CONNECTED) {
    digitalWrite(RED_LED, HIGH);
    delay(100);
    digitalWrite(RED_LED, LOW);
    delay(250);
  }
  digitalWrite(RED_LED, HIGH);
  Serial.println(); 
  Serial.println(WiFi.localIP());
  
  timeClient.begin();
  timeClient.update();
  Serial.println("NDP synced. Setup complete!");
  randomSeed(analogRead(0));  // TODO fix this, this is terrible 
}

double get_temperature_lm35() {
  // ADC correction required for dev board
  int analogIn = analogRead(A0) - 15;
  float voltage = (analogIn / 1024.0) * ADC_REF_VOLTAGE;
  float temp = voltage * 100;
  Serial.print(analogIn);
  Serial.print(" - ");
  return temp;
}

unsigned long nextSensorUpdateTime = 0;
int sensorUpdateInterval = 5;

long long generateNonce() {
  // TODO make this 64 bit 
  return random(0, 100000000);
}

std::string createPacket(long long nonce, unsigned long timestamp, float temperature, int sensorId) {
  StaticJsonDocument<70> doc;
  doc["temperature"] = temperature;
  doc["nonce"] = nonce;
  doc["timestamp"] = timestamp;
  doc["sensor_id"] = sensorId;
  std::string j;
  serializeJson(doc, j);
  return j;
}

int postPacket(std::string packet) {
  // setInsecure means we do not check the certificate at all
  // This means that the SSL will encrypt the data, but will not verify identifiy of the server
  // Therefore MITM attacks are possible. SSL really adds no real security. Instead we must generate
  // our own signature (TODO)
  wifiClient.setInsecure();
  httpClient.begin(wifiClient, endpoint);
  httpClient.addHeader("Content-Type", "application/json");
  httpClient.addHeader("x-api-key", API_KEY);
  return httpClient.POST(packet.c_str());
}

void loop() {
  unsigned long currentTime = timeClient.getEpochTime();
  if (currentTime >= nextSensorUpdateTime) {
    nextSensorUpdateTime = currentTime + sensorUpdateInterval;
    timeClient.update();
    double temp = get_temperature_lm35();
    long long nonce = generateNonce();
    std::string packet = createPacket(nonce, currentTime, temp, SENSOR_ID);
    int status = postPacket(packet);
    Serial.println(status);
  }
  delay(100);
}
