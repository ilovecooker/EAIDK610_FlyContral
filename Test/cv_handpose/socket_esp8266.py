import socket



def send_cmd(cmd_char):
    if(sock.send(cmd_char.encode())>0):
        response = sock.recv(1024)
        print('接收到ESP8266回应:', response.decode())
    elif(sock.send(cmd_char.encode())<0):
        print("发送UDP消息失败\n")
        for i in range(3):
            flag=sock.send(cmd_char.encode())
        if(flag<0):
            raise ValueError("未收到预期的ESP8266响应\n")
    elif(sock.send(cmd_char.encode())==0):
        print("发送空消息\n")
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
    if (response.decode()=="Hello From ESP8266!"):
        print('成功连接到ESP8266.')

except ConnectionRefusedError:
    print('连接ESP8266失败！！！')
except ValueError as e:
    print('错误：', str(e))
finally:
    # 关闭 Socket 连接
    sock.close()
