#include <Servo.h>



int ch_width_1 = 0, ch_width_2 = 0, ch_width_3 = 0, ch_width_4 = 0, ch_width_5 = 0, ch_width_6 = 0;
Servo ch1; Servo ch2; Servo ch3; Servo ch4; Servo ch5; Servo ch6;

struct Signal {    
  byte roll;
  byte pitch;
  byte throttle;  
  byte yaw;
  byte flymod;
};
Signal data;

void ResetData()
{
  data.roll = 127; // 横滚通道中心点（254/2 = 127）
  data.pitch = 127; // 俯仰通道
  data.throttle = 0; // 信号丢失时，关闭油门
  data.yaw = 127; // 航向通道
  data.flymod = 0; //第五通道
}

int input1=A1;
int input2=A2;
int input3=A3;
int input4=A4; 


void setup(){
  Serial.begin(9600);

  //设置PWM信号输出引脚
  ch1.attach(3);
  ch2.attach(5);
  ch3.attach(6);
  ch4.attach(9);
  ch5.attach(10);

  ResetData();
}

void mod(){
  if(digitalRead(input1) == HIGH && digitalRead(input2) == HIGH && digitalRead(input3) == HIGH&& digitalRead(input4) == HIGH){
    data.throttle = 0;
    data.yaw = 255;
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == LOW && digitalRead(input3) == LOW&& digitalRead(input4) == LOW){
    data.throttle = 0;
    data.yaw = 0;
    data.flymod = 0;
  }
  else if(digitalRead(input1) == HIGH && digitalRead(input2) == LOW && digitalRead(input3) == HIGH&& digitalRead(input4) == LOW){       
    data.flymod = 0;
    data.throttle = 0;
  }
  else if(digitalRead(input1) == HIGH && digitalRead(input2) == LOW && digitalRead(input3) == LOW&& digitalRead(input4) == LOW){  
    data.flymod = 255;
    data.pitch = 75;
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == LOW && digitalRead(input3) == LOW&& digitalRead(input4) == HIGH){
    if(data.flymod == 0){
      data.throttle = 0;
    }      
    data.pitch = 200; 
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == HIGH && digitalRead(input3) == LOW&& digitalRead(input4) == LOW){
    if(data.flymod == 0){
      data.throttle = 0;
    }      
    data.roll = 75; 
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == LOW && digitalRead(input3) == HIGH&& digitalRead(input4) == LOW){
    if(data.flymod == 0){
      data.throttle = 0;
    }      
    data.roll = 200; 
  }
  else if(digitalRead(input1) == HIGH && digitalRead(input2) == HIGH && digitalRead(input3) == LOW&& digitalRead(input4) == LOW){
    if(data.flymod == 0){
      data.throttle = 0;
      return;
    }      
    data.throttle = 200; 
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == LOW && digitalRead(input3) == HIGH&& digitalRead(input4) == HIGH){
    if(data.flymod == 0){
      data.throttle = 0;
      return;
    }      
    data.throttle = 75; 
  }
  else if(digitalRead(input1) == HIGH && digitalRead(input2) == HIGH && digitalRead(input3) == HIGH&& digitalRead(input4) == LOW){
    if(data.flymod == 0){
      data.throttle = 0;
    }      
    data.yaw = 75;  
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == HIGH && digitalRead(input3) == HIGH&& digitalRead(input4) == HIGH){
    if(data.flymod == 0){
      data.throttle = 0;
    }      
    data.yaw = 200;  
  }
  else if(digitalRead(input1) == LOW && digitalRead(input2) == HIGH && digitalRead(input3) == HIGH&& digitalRead(input4) == LOW){
    if(data.flymod == 0){
      data.roll = 127;
      data.pitch = 127; 
      data.throttle = 0; 
      data.yaw = 127;
      return;
    }      
    data.roll = 127;
    data.pitch = 127; 
    data.throttle = 127; 
    data.yaw = 127;  
  }
  else{
    data.roll = 127;
    data.pitch = 127; 
    data.throttle = 127; 
    data.yaw = 127;  
  }
}
void loop()
{
  mod();

  ch_width_1 = map(data.roll,     0, 255, 1000, 2000);// 将0~255映射到1000~2000，即1ms~2ms/20ms的PWM输出
  ch_width_2 = map(data.pitch,    0, 255, 1000, 2000);
  ch_width_3 = map(data.throttle, 0, 255, 1000, 2000);
  ch_width_4 = map(data.yaw,      0, 255, 1000, 2000);
  ch_width_5 = map(data.flymod,      0, 255, 1000, 2000);


  Serial.print("\t");Serial.print(ch_width_1);
  Serial.print("\t");Serial.print(ch_width_2);
  Serial.print("\t");Serial.print(ch_width_3);
  Serial.print("\t");Serial.print(ch_width_4);
  Serial.print("\t");Serial.print(ch_width_5);
  Serial.println("");

  // 将PWM信号输出至引脚
  ch1.writeMicroseconds(ch_width_1);//写入us值
  ch2.writeMicroseconds(ch_width_2);
  ch3.writeMicroseconds(ch_width_3);
  ch4.writeMicroseconds(ch_width_4);
  ch5.writeMicroseconds(ch_width_5);
}