import processing.serial.*;
import processing.data.JSONObject;
PImage mapDisplay;  // maskelenmiş ve boyutlandırılmış nihai harita görüntüsü


Serial serialPort;
String rawLine = "";

// Telemetry values
float roll = 0, pitch = 0, yaw = 0;
float temperature = 0, pressure = 0, altitude = 0;
String gpsTime = "", gpsLat = "", gpsLon = "";

// Map vars
int mapZoom = 15;
double mapLat = 0, mapLon = 0;
boolean mapUpdated = false;
PImage mapImg;
PImage mapMask;

// GUI state
String[] ports;
int[] bauds = {9600, 57600, 115200, 230400, 921600};
int selPort = -1, selBaud = -1;
boolean showPortList = false, showBaudList = false;
boolean isConnected = false;

void setup() {
  // Uydu karoları için User-Agent
  System.setProperty("http.agent", "ProcessingLiveMap/1.0 (your_email@example.com)");

  size(700, 600);
  ports = Serial.list();
  textFont(createFont("Consolas", 12));
  // Başlangıçta maske placeholder
  mapMask = createImage(1, 1, ARGB);
}

void draw() {
  background(0);
  drawDropdowns();

  // 1) Altitude tape (sol)
  drawAltitudeTape(100, height/2, 400, altitude);

  // 2) Artificial Horizon (ortada)
  drawArtificialHorizon(width/2, height/2, 400);

  // 3) Roll/Pitch metni
  fill(255);
  textAlign(CENTER, BOTTOM);
  text(String.format("Roll: %.1f°   Pitch: %.1f°", roll, pitch),
       width/2, height/2 - 220);

  // 4) Yaw pusulası
  float yawCx = width - 90, yawCy = 120 + 400;
  float r = 50;
  drawYawIndicator(yawCx, yawCy, r);

  // 4b) Canlı uydu haritası (çap = 2*r)
  float rMap = r * 1.5 ;
  drawMapIndicator(yawCx, yawCy, rMap);

  // 5) Basınç & Sıcaklık (sağ)
  float boxW = 120, boxH = 24, spacing = 10;
  float boxX = width - boxW - 180;
  float midY = height/1.075 - (boxH + spacing)/2;
  stroke(0,255,0); fill(0);
  rect(boxX, midY, boxW, boxH);
  noStroke(); fill(0,255,0);
  textAlign(CENTER, CENTER);
  text(String.format("P: %.1f hPa", pressure),
       boxX-65 + boxW/2, midY + boxH/2-12.5);
  float tY = midY + boxH + spacing;
  stroke(0,255,0); fill(0);
  rect(boxX, tY, boxW, boxH);
  noStroke(); fill(0,255,0);
  textAlign(CENTER, CENTER);
  text(String.format("T: %.1f°C", temperature),
       boxX-73 + boxW/2, tY-12.5 + boxH/2);

  // 6) Yükseklik (sol üst)
  fill(0,255,0);
  textAlign(LEFT, TOP);
  text(String.format("Alt: %.1f m", altitude), 70, 70);

  // 7) GPS bloğu (alt sol)
  float gpsX = 130, gpsBoxW = 240, gpsBoxH = 80;
  float gpsBoxY = height - gpsBoxH + 50;
  fill(0,255,0);
  textAlign(CENTER, BOTTOM);
  text("GPS", gpsX - 110 + gpsBoxW/2, gpsBoxY - 15);
  stroke(0,255,0); fill(0);
  rect(gpsX, gpsBoxY - 10, gpsBoxW, gpsBoxH - 20);
  noStroke(); fill(0,255,0);
  textAlign(LEFT, TOP);
  text("Time: " + gpsTime, gpsX - 110, gpsBoxY - 30);
  text("Lat:  " + gpsLat,  gpsX - 110, gpsBoxY - 15);
  text("Lon:  " + gpsLon,  gpsX - 110, gpsBoxY + 0);
  text("GPS", gpsX - 120, gpsBoxY-55);
}

void drawDropdowns() {
  float bx = width - 60, by2 = 25, bw = 100, bh = 30;
  fill(isConnected ? color(255,0,0) : color(0,255,0));
  rectMode(CENTER); rect(bx, by2, bw, bh);
  fill(0);
  textAlign(CENTER, CENTER);
  text(isConnected ? "Disconnect" : "Connect", bx, by2);

  float ddX = bx - 100, comY = by2 + 30, h = 24, w = 140;
  // COM dropdown
  fill(50); rectMode(CORNER); rect(ddX, comY, w, h);
  fill(255); textAlign(LEFT, CENTER);
  text(selPort>=0 ? ports[selPort] : "Select COM", ddX+4, comY+h/2);
  triangle(ddX+w, comY+4, ddX+w+14, comY+4, ddX+w+7, comY+14);
  if (showPortList) {
    for (int i=0; i<ports.length; i++){
      fill(i==selPort?100:75);
      rect(ddX, comY+h+i*h, w, h);
      fill(255);
      text(ports[i], ddX+4, comY+h+i*h+h/2);
    }
  }
  // Baud dropdown
  float baudY = comY + h + (showPortList?ports.length*h:0);
  fill(50); rect(ddX, baudY, w, h);
  fill(255);
  text(selBaud>=0 ? str(bauds[selBaud]) : "Select Baud", ddX+4, baudY+h/2);
  triangle(ddX+w, baudY+4, ddX+w+14, baudY+4, ddX+w+7, baudY+14);
  if (showBaudList) {
    for (int i=0; i<bauds.length; i++){
      fill(i==selBaud?100:75);
      rect(ddX, baudY+h+i*h, w, h);
      fill(255);
      text(str(bauds[i]), ddX+4, baudY+h+i*h+h/2);
    }
  }
}

void mousePressed() {
  int mx = mouseX, my = mouseY;
  float bx = width - 60, by2 = 25, bw = 100, bh = 30;
  if (mx>=bx-bw/2 && mx<=bx+bw/2 && my>=by2-bh/2 && my<=by2+bh/2) {
    if (!isConnected && selPort>=0 && selBaud>=0) {
      serialPort = new Serial(this, ports[selPort], bauds[selBaud]);
      serialPort.bufferUntil('\n');
      isConnected = true;
    } else if (isConnected) {
      serialPort.stop();
      serialPort = null;
      isConnected = false;
    }
    return;
  }
  float ddX = bx - 90, comY = by2 + 30, h = 24, w = 140;
  if (mx>=ddX && mx<=ddX+w && my>=comY && my<=comY+h) {
    showPortList = !showPortList;
    showBaudList = false;
    return;
  }
  if (showPortList) {
    for (int i=0; i<ports.length; i++){
      float y0 = comY + h + i*h;
      if (mx>=ddX && mx<=ddX+w && my>=y0 && my<=y0+h) {
        selPort = i;
        showPortList = false;
      }
    }
  }
  float baudY = comY + h + (showPortList?ports.length*h:0);
  if (mx>=ddX && mx<=ddX+w && my>=baudY && my<=baudY+h) {
    showBaudList = !showBaudList;
    showPortList = false;
    return;
  }
  if (showBaudList) {
    for (int i=0; i<bauds.length; i++){
      float y0 = baudY + h + i*h;
      if (mx>=ddX && mx<=ddX+w && my>=y0 && my<=y0+h) {
        selBaud = i;
        showBaudList = false;
      }
    }
  }
}

void serialEvent(Serial p) {
  String s = p.readStringUntil('\n');
  if (s == null) return;
  rawLine = s.trim();
  parseTelemetryJSON(rawLine);
}

void parseTelemetryJSON(String jsonLine) {
  try {
    JSONObject json = JSONObject.parse(jsonLine);
    roll        = json.getFloat("roll");
    pitch       = json.getFloat("pitch");
    yaw         = json.getFloat("yaw");
    temperature = json.getFloat("bmp_temperature");
    pressure    = json.getFloat("bmp_pressure");
    altitude    = json.getFloat("bmp_altitude");

    gpsTime = json.hasKey("gps_time") ? json.getString("gps_time") : "";

    if (json.hasKey("gps_latitude")) {
      mapLat = json.getDouble("gps_latitude");
      gpsLat = String.valueOf(mapLat);
    } else gpsLat = "";
    if (json.hasKey("gps_longitude")) {
      mapLon = json.getDouble("gps_longitude");
      gpsLon = String.valueOf(mapLon);
    } else gpsLon = "";

    if (!gpsLat.isEmpty() && !gpsLon.isEmpty()) mapUpdated = true;
  } catch (Exception e) {
    println("JSON parse error: " + e.getMessage());
  }
}

void drawAltitudeTape(float cx, float cy, float h, float alt) {
  float w    = 60;
  float topY = cy - h/2;
  float botY = cy + h/2;

  // Arka plan bandı
  noStroke();
  fill(50);
  rectMode(CENTER);
  rect(cx, cy, w, h);

  // Ölçek çizgileri
  stroke(255);
  strokeWeight(2);
  float minor = 200;
  float major = 1000;
  // Artık 0–8000 metre arası
  for (float a = 0; a <= 8000; a += minor) {
    float y = map(a, 0, 8000, botY, topY);
    float len = (abs(a % major) < 1e-3) ? w * 0.4f : w * 0.2f;
    line(cx - w/2, y, cx - w/2 + len, y);
    if (abs(a % major) < 1e-3) {
      noStroke();
      fill(255);
      textAlign(RIGHT, CENTER);
      text((int)a, cx - w/2 - 5, y);
      stroke(255);
    }
  }

  // Mevcut yüksekliği gösteren çizgi
  float mY = map(alt, 0, 8000, botY, topY);
  stroke(0, 255, 0);
  strokeWeight(3);
  line(cx - w/2, mY, cx + w/2, mY);

  // Yükseklik kutucuğu
  noFill();
  stroke(255);
  rectMode(CENTER);
  rect(cx, mY, w + 20, 30);

  // Yüksekliği yaz
  fill(255);
  noStroke();
  textAlign(CENTER, CENTER);
  text(nf(alt, 0, 0), cx, mY);
}

void drawArtificialHorizon(float cx, float cy, int d) {
  PGraphics pg = createGraphics(width, height);
  pg.beginDraw();
    pg.clear(); pg.noStroke(); pg.translate(cx, cy);
    float maxP = 90;
    float py = map(pitch, -maxP, maxP, -d/2, d/2);
    pg.translate(0, py); pg.rotate(-radians(roll));
    pg.fill(30,144,255); pg.rect(-d, -2*d, 2*d, 2*d);
    pg.fill(139,69,19); pg.rect(-d, 0, 2*d, 2*d);
    pg.stroke(255); pg.strokeWeight(2); pg.fill(255);
    for (int L=-90; L<=90; L+=10) {
      if (L==0) continue;
      float y = map(L, -maxP, maxP, -d/2, d/2);
      float len = (L%30==0)? d*0.30f : d*0.20f;
      pg.line(-len, y, len, y);
      if (abs(L)%30==0) {
        pg.textAlign(CENTER,CENTER);
        pg.text(abs(L), len+20, y);
        pg.text(abs(L), -len-20, y);
      }
    }
  pg.endDraw();
  PGraphics mask = createGraphics(width, height);
  mask.beginDraw();
    mask.background(0); mask.noStroke(); mask.fill(255);
    mask.ellipse(cx, cy, d, d);
  mask.endDraw();
  pg.mask(mask);
  image(pg,0,0);
  stroke(255); strokeWeight(3);
  line(cx-d/2, cy, cx+d/2, cy);
  noFill(); stroke(255); strokeWeight(4);
  ellipse(cx, cy, d, d);
  stroke(255,255,0); strokeWeight(4);
  float w2 = d*0.15f;
  line(cx-w2, cy, cx+w2, cy);
  line(cx, cy-10, cx, cy+10);
}

void drawYawIndicator(float cx, float cy, float r) {
  // Metnin orijinal yerde kalması için önceki kaydırmayı koruyoruz
  cx += 15;
  cy -= 215;
  float rScaled = r * 0.8f;

  // Sadece yaw metni
  fill(255);
  noStroke();
  textFont(createFont("Consolas", (int)(rScaled * 0.3f)));
  textAlign(CENTER, CENTER);
  text("Yaw: " + nf(yaw, 1, 1) + "°", cx-20, cy + 30 + rScaled * 1.3f);
  text("<L E F A S   T E A M>" , cx-540, cy-290);
}

void drawMapIndicator(float cx, float cy, float r) {
  pushStyle();
    // 1) Pozisyonu ayarla
    cx -= 10;
    cy -= 20;

    // 2) Hala bağlanmadıysa uyarıyı göster ve çık
    if (!isConnected) {
      noFill();
      stroke(0, 255, 0);
      strokeWeight(2);
      ellipse(cx, cy, 2 * r, 2 * r);

      fill(0, 255, 0);
      noStroke();
      textAlign(CENTER, CENTER);
      textFont(createFont("Consolas", 13));
      float lineH = textAscent() + textDescent();
      text("Connection required", cx, cy - lineH);
      text("for map",             cx, cy);
      text("display.",            cx, cy + lineH);

      popStyle();
      return;
    }

    // 3) Sadece GPS verisi gelince bir kere tile oluştur
    if (mapUpdated) {
      buildMapTile(
        (int)round(mapZoom * 1.05f),
        (float)mapLat,
        (float)mapLon,
        r
      );
      mapUpdated = false;
    }

    // 4) Eğer hazırsa önceden maskelenmiş display’i çiz
    if (mapDisplay != null) {
      image(mapDisplay, cx - r, cy - r);
    }

    // 5) Daire çerçevesi, tick’ler, yön etiketleri, uçak ikonu (eski kodu aynen koruyun)
    noFill(); stroke(0, 255, 0); strokeWeight(2);
    ellipse(cx, cy, 2 * r, 2 * r);

    // tick’ler
    strokeWeight(1); textFont(createFont("Consolas",10)); fill(0,255,0);
    for (int angle=0; angle<360; angle+=30) {
      float a = radians(angle) - HALF_PI;
      float ti = r*0.9f, to = r;
      line(cx+cos(a)*ti, cy+sin(a)*ti,
           cx+cos(a)*to, cy+sin(a)*to);
      text(angle+"°",
           cx+cos(a)*r*1.15f, cy+sin(a)*r*1.15f);
    }

    // N/E/S/W
    textFont(createFont("Consolas",18));
    stroke(255,0,0); fill(255,0,0);
    float cr = r*0.75f;
    text("N", cx,         cy-cr);
    text("E", cx+cr,      cy);
    text("S", cx,         cy+cr);
    text("W", cx-cr,      cy);

    // uçak ikonu
    float s = r * 0.14f;
    pushMatrix();
      translate(cx, cy);
      rotate(radians((float)yaw));
      noStroke(); fill(255,0,0);
      beginShape();
        vertex(0,    -s * 1.5f);
        vertex(s,    s * 0.5f);
        vertex(0,    0);
        vertex(-s,   s * 0.5f);
      endShape(CLOSE);
    popMatrix();

  popStyle();
}
void buildMapTile(int z, float flat, float flon, float r) {
  int xt = (int)((flon + 180) / 360 * (1 << z));
  double mercN = Math.log(Math.tan(radians(flat)) + 1.0 / Math.cos(radians(flat)));
  int yt = (int)((1 - mercN/PI) / 2 * (1 << z));

  String url = String.format(
    "https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/"
    + "MapServer/tile/%d/%d/%d.png",
    z, yt, xt
  );
  mapImg = loadImage(url);

  int d = (int)(2 * r);
  mapMask = createImage(d, d, ARGB);
  mapMask.loadPixels();
  for (int y = 0; y < d; y++) {
    for (int x = 0; x < d; x++) {
      float dx = x - r, dy = y - r;
      mapMask.pixels[y*d + x] =
        (dx*dx + dy*dy <= r*r) ? color(255) : color(0);
    }
  }
  mapMask.updatePixels();

  mapDisplay = mapImg.copy();
  mapDisplay.resize(d, d);
  mapDisplay.mask(mapMask);
}
