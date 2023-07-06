#include <SoftwareSerial.h>
// 引入 ESP8266WiFi 库
#include <ESP8266WiFi.h>
#include <WiFiUdp.h>

char ssid[] = "Esp8266ApTest";         // 定义 WiFi 热点名字
char password[] = "12345678";          // 定义 WiFi 热点密码
char hello[] = "Hello, ESP8266!";
int flag_error=0;
int flag_keep=0;
unsigned long currentTime = millis();
unsigned long startTime = millis(); 
WiFiUDP udp;
int udpPort = 8888;                    // 指定 UDP 端口号

void setup() {
  Serial.begin(9600);
  // 初始化 ESP8266 WiFi 模块
  WiFi.softAP(ssid, password);        // 将ESP8266设置为WiFi AP模式
  IPAddress myIP = WiFi.softAPIP();   // 获取WiFi AP IP
  udp.begin(udpPort);                 // 启动UDP服务
  Serial.print("AP IP address: ");
  Serial.println(myIP);
  pinMode(D0, OUTPUT);
  pinMode(D1, OUTPUT);
  pinMode(D2, OUTPUT);
  pinMode(D3, OUTPUT);
  
  digitalWrite(D0, LOW);
  digitalWrite(D1, HIGH);
  digitalWrite(D2, HIGH);
  digitalWrite(D3, LOW);  
}

void fly_mod(char mod)
{
  switch(mod) {
    case 'r':
      digitalWrite(D0, HIGH);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, HIGH);
      Serial.println("解锁");
      break;
    case 'l':
      digitalWrite(D0, LOW);
      digitalWrite(D1, LOW);
      digitalWrite(D2, LOW);
      digitalWrite(D3, LOW);
      Serial.println("上锁");
      break;
    case 'p':
      digitalWrite(D0, HIGH);
      digitalWrite(D1, LOW);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, LOW);
      Serial.println("制动");
      break;
    case 'w':
      digitalWrite(D0, HIGH);
      digitalWrite(D1, LOW);
      digitalWrite(D2, LOW);
      digitalWrite(D3, LOW);
      Serial.println("前进");
      break;
    case 's':
      digitalWrite(D0, LOW);
      digitalWrite(D1, LOW);
      digitalWrite(D2, LOW);
      digitalWrite(D3, HIGH);
      Serial.println("后退");
      break;
    case 'a':
      digitalWrite(D0, LOW);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, LOW);
      digitalWrite(D3, LOW);
      Serial.println("左移");
      break;
    case 'd':
      digitalWrite(D0, LOW);
      digitalWrite(D1, LOW);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, LOW);
      Serial.println("右移");
      break;
    case 'u':
      digitalWrite(D0, HIGH);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, LOW);
      digitalWrite(D3, LOW);
      Serial.println("上升");
      break;
    case 'n':
      digitalWrite(D0, LOW);
      digitalWrite(D1, LOW);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, HIGH);
      Serial.println("下降");
      break;
    case 'q':
      digitalWrite(D0, HIGH);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, LOW);
      Serial.println("左转");
      break;
    case 'e':
      digitalWrite(D0, LOW);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, HIGH);
      Serial.println("右转");
      break;
    case 'k':
      digitalWrite(D0, LOW);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, LOW);
      Serial.println("保持1");
      break;
    default:
      digitalWrite(D0, LOW);
      digitalWrite(D1, HIGH);
      digitalWrite(D2, HIGH);
      digitalWrite(D3, LOW);
      Serial.println("保持2");
  }
  return;
}
void loop() {
  // 检测是否接收到消息
  int packageSize = udp.parsePacket();
  if(packageSize < 0){
    currentTime = millis();
    unsigned long elapsedTime = (currentTime - startTime) / 1000;
    if(elapsedTime>1)
    {
      Serial.println(elapsedTime);
      fly_mod('p');      
    }
    if(elapsedTime>1)
    {
      Serial.println(elapsedTime);
      fly_mod('p');      
    }    
  }
  if (packageSize > 0) {
    startTime = millis();
    // 读取发送者信息与数据包内容
    String sender = udp.remoteIP().toString();
    int senderPort = udp.remotePort();    
    char packetBuffer[packageSize];
    udp.read(packetBuffer, packageSize);

    // 打印消息内容
    Serial.print("Received message from ");
    Serial.print(sender);
    Serial.print(":");
    Serial.println(senderPort);
    char rx[50];
    strncpy(rx, packetBuffer, packageSize);
    rx[packageSize]='\0';
    // 发送回复
    if(strcmp(rx,hello) == 0)
    {
      Serial.println("ok");      
      String responseStr = "Hello From ESP8266!";
      udp.beginPacket(udp.remoteIP(), udp.remotePort());
      udp.write(responseStr.c_str(), responseStr.length());
      udp.endPacket();
    }
    else
    {
      String responseStr = "ok";
      Serial.print("cmd=");
      char mod;
      Serial.println(rx[0]);
      fly_mod(rx[0]);
      udp.beginPacket(udp.remoteIP(), udp.remotePort());
      udp.write(responseStr.c_str(), responseStr.length());
      udp.endPacket();
    }    
  }
}
