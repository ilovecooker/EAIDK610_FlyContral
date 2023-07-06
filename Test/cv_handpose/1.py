import cv2
from cvzone.HandTrackingModule import HandDetector
import math
import time
import socket

def send_cmd(cmd_char):
    if(sock.send(cmd_char.encode())>0):
        response = sock.recv(1024)
        print('接收到ESP8266回应:', response.decode())
    elif(sock.send(cmd_char.encode())<0):
        print("发送UDP消息失败\n")
        for i in range(20):
            flag=sock.send(cmd_char.encode())
        if(flag<0):
            raise ValueError("未收到预期的ESP8266响应\n")
    elif(sock.send(cmd_char.encode())==0):
        print("发送空消息\n")
def send_flycontrol(last_cmd,current_cmd):
    if(last_cmd!=current_cmd):
        send_cmd(current_cmd)
    else:
        return

def vector_2d_angle(v1,v2):
    '''
        求解二维向量的角度
    '''
    v1_x=v1[0]
    v1_y=v1[1]
    v2_x=v2[0]
    v2_y=v2[1]
    try:
        angle_= math.degrees(math.acos((v1_x*v2_x+v1_y*v2_y)/(((v1_x**2+v1_y**2)**0.5)*((v2_x**2+v2_y**2)**0.5))))
    except:
        angle_ =65535.
    if angle_ > 180.:
        angle_ = 65535.
    return angle_
def hand_angle(hand_):
    '''
        获取对应手相关向量的二维角度,根据角度确定手势
    '''
    angle_list = []
    #---------------------------- thumb 大拇指角度
    angle_ = vector_2d_angle(
        ((int(hand_[0][0])- int(hand_[2][0])),(int(hand_[0][1])-int(hand_[2][1]))),
        ((int(hand_[3][0])- int(hand_[4][0])),(int(hand_[3][1])- int(hand_[4][1])))
        )
    angle_list.append(angle_)
    #---------------------------- index 食指角度
    angle_ = vector_2d_angle(
        ((int(hand_[0][0])-int(hand_[6][0])),(int(hand_[0][1])- int(hand_[6][1]))),
        ((int(hand_[7][0])- int(hand_[8][0])),(int(hand_[7][1])- int(hand_[8][1])))
        )
    angle_list.append(angle_)
    #---------------------------- middle 中指角度
    angle_ = vector_2d_angle(
        ((int(hand_[0][0])- int(hand_[10][0])),(int(hand_[0][1])- int(hand_[10][1]))),
        ((int(hand_[11][0])- int(hand_[12][0])),(int(hand_[11][1])- int(hand_[12][1])))
        )
    angle_list.append(angle_)
    #---------------------------- ring 无名指角度
    angle_ = vector_2d_angle(
        ((int(hand_[0][0])- int(hand_[14][0])),(int(hand_[0][1])- int(hand_[14][1]))),
        ((int(hand_[15][0])- int(hand_[16][0])),(int(hand_[15][1])- int(hand_[16][1])))
        )
    angle_list.append(angle_)
    #---------------------------- pink 小拇指角度
    angle_ = vector_2d_angle(
        ((int(hand_[0][0])- int(hand_[18][0])),(int(hand_[0][1])- int(hand_[18][1]))),
        ((int(hand_[19][0])- int(hand_[20][0])),(int(hand_[19][1])- int(hand_[20][1])))
        )
    angle_list.append(angle_)
    return angle_list

def h_gesture(angle_list):
    '''
        # 二维约束的方法定义手势
        # fist five gun love one six three thumbup yeah
    '''
    thr_angle = 65.
    thr_angle_thumb = 53.
    thr_angle_s = 49.
    gesture_str = None
    if 65535. not in angle_list:
        if (angle_list[0]>thr_angle_thumb) and (angle_list[1]>thr_angle) and (angle_list[2]>thr_angle) and (angle_list[3]>thr_angle) and (angle_list[4]>thr_angle):
            gesture_str = "fist"
        elif (angle_list[0]<thr_angle_s) and (angle_list[1]<thr_angle_s) and (angle_list[2]<thr_angle_s) and (angle_list[3]<thr_angle_s) and (angle_list[4]<thr_angle_s):
            gesture_str = "five"
        elif (angle_list[0]<thr_angle_s)  and (angle_list[1]<thr_angle_s) and (angle_list[2]>thr_angle) and (angle_list[3]>thr_angle) and (angle_list[4]>thr_angle):
            gesture_str = "gun"
        elif (angle_list[0]<thr_angle_s)  and (angle_list[1]<thr_angle_s) and (angle_list[2]>thr_angle) and (angle_list[3]>thr_angle) and (angle_list[4]<thr_angle_s):
            gesture_str = "love"
        elif (angle_list[0]>5)  and (angle_list[1]<thr_angle_s) and (angle_list[2]>thr_angle) and (angle_list[3]>thr_angle) and (angle_list[4]>thr_angle):
            gesture_str = "one"
        elif (angle_list[0]<thr_angle_s)  and (angle_list[1]>thr_angle) and (angle_list[2]>thr_angle) and (angle_list[3]>thr_angle) and (angle_list[4]>thr_angle):
            gesture_str = "thumbUp"
        elif (angle_list[0]>thr_angle_thumb)  and (angle_list[1]<thr_angle_s) and (angle_list[2]<thr_angle_s) and (angle_list[3]>thr_angle) and (angle_list[4]>thr_angle):
            gesture_str = "two"
        elif (angle_list[0]>5)  and (angle_list[1]>thr_angle_s) and (angle_list[2]<thr_angle_s) and (angle_list[3]<thr_angle) and (angle_list[4]<thr_angle):
            gesture_str = "ok"
        elif (angle_list[0]>thr_angle_thumb)  and (angle_list[1]<thr_angle_s) and (angle_list[2]<thr_angle_s) and (angle_list[3]<thr_angle_s) and (angle_list[4]>thr_angle):
            gesture_str = "three"
    return gesture_str
def detect():
    cap = cv2.VideoCapture(0)
    cap.set(3, 1280)  # 设置高度
    cap.set(4, 720)  # 设置宽度
    detector = HandDetector(detectionCon=0.7)  # 设置阈值
    start = time.time_ns()/1000000000.0
    fps_sum=0
    gesture_str_left = "no gesture"
    gesture_str_right = "no gesture"
    gesture="hold on"
    last_cmd='x'
    cmd = 'k'
    while True:
        leftHands_landmarks = []
        rightHands_landmarks = []
        success, img = cap.read()
        hands, img = detector.findHands(img)
        img = cv2.flip(img, 1)
        if(len(hands)==2 and hands[0]["type"]!=hands[1]["type"]):
            for i in range(len(hands)):
                if(hands[i]["type"]=="Left"):
                    for j in range(21):
                        x = hands[i]["lmList"][j][0]
                        y = hands[i]["lmList"][j][1]
                        leftHands_landmarks.append((x, y))
                    continue
                if(hands[i]["type"]=="Right"):
                    for j in range(21):
                        x = hands[i]["lmList"][j][0]
                        y = hands[i]["lmList"][j][1]
                        rightHands_landmarks.append((x, y))
                    continue
            angle_list_left = hand_angle(leftHands_landmarks)
            angle_list_right = hand_angle(rightHands_landmarks)
            gesture_str_left = h_gesture(angle_list_left)
            gesture_str_right = h_gesture(angle_list_right)
            cv2.putText(img, gesture_str_left, (0, 100), 0, 1.3, (0, 0, 255), 3)
            cv2.putText(img, gesture_str_right, (800, 100), 0, 1.3, (0, 0, 255), 3)
        else:
            gesture = "hold on"
            send_cmd('k')
        if(gesture_str_left=="ok" and gesture_str_right=="ok"):
            cmd='r'
            gesture="unlock"
        elif((gesture_str_left=="love" and gesture_str_right=="ok") or(gesture_str_left=="ok" and gesture_str_right=="love")):
            cmd='l'
            gesture="lock"
        elif(gesture_str_left=="love" and gesture_str_right=="love"):
            cmd='p'
            gesture="stop"
        elif(gesture_str_left=="gun" and gesture_str_right=="gun"):
            cmd='w'
            gesture="forward"
        elif(gesture_str_left=="thumbUp" and gesture_str_right=="thumbUp"):
            cmd='s'
            gesture="back"
        elif(gesture_str_left=="thumbUp" and gesture_str_right=="five"):
            cmd='a'
            gesture="turn left"
        elif(gesture_str_left=="five" and gesture_str_right=="thumbUp"):
            cmd='d'
            gesture="turn right"
        elif((gesture_str_left=="one" and gesture_str_right=="five") or (gesture_str_left=="five" and gesture_str_right=="one")):
            cmd='u'
            gesture="turn up"
        elif((gesture_str_left=="one" and gesture_str_right=="fist") or (gesture_str_left=="fist" and gesture_str_right=="one")):
            cmd='n'
            gesture="turn down"
        elif((gesture_str_left=="three" and gesture_str_right=="five") or (gesture_str_left=="five" and gesture_str_right=="three")):
            cmd='q'
            gesture="yam to left"
        elif((gesture_str_left=="three" and gesture_str_right=="fist") or (gesture_str_left=="fist" and gesture_str_right=="three")):
            cmd='e'
            gesture="yam to right"
        else:
            cmd='k'
            gesture="hold on"
        send_flycontrol(last_cmd,cmd)
        last_cmd=cmd
        end=time.time_ns()/1000000000.0
        fps_sum=fps_sum+1
        fps=fps_sum/(end-start)
        cv2.putText(img, "fps : "+str(fps), (0, 600), 0, 0.9, (0, 0, 255), 1)
        cv2.putText(img, gesture, (400, 100), 0, 1, (0, 0, 255), 1)
        cv2.imshow("gestureHand", img)
        cv2.waitKey(1)

if __name__ == '__main__':
    # 设置 ESP8266 的 IP 地址和端口号
    esp_ip = '192.168.4.1'  # 替换为 ESP8266 的实际 IP 地址
    esp_port = 8888  # 替换为 ESP8266 的实际端口号
    # 创建 UDP Socket 对象
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    try:
        # 尝试连接 ESP8266
        sock.connect((esp_ip, esp_port))

        # 发送数据到 ESP8266
        message = 'Hello, ESP8266!'
        sock.send(message.encode())

        # 等待接收来自 ESP8266 的响应
        response = sock.recv(1024)
        print('Response from ESP8266:', response.decode())
        if (response.decode() == "Hello From ESP8266!"):
            print('成功连接到ESP8266.')
        detect()
        send_cmd('p')
    except ConnectionRefusedError:
        print('连接ESP8266失败！！！')
        send_cmd('p')
    except ValueError as e:
        print('错误：', str(e))
        send_cmd('p')
    except Exception as e:
        print('错误：', str(e))
        send_cmd('p')
    finally:
        # 关闭 Socket 连接
        send_cmd('p')
        sock.close()