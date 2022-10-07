extends Node2D

# http://www.hivemq.com/demos/websocket-client/
var server = "broker.mqttdashboard.com"
var port = 1883
var client_id = "mqtt-explorer-943ee806"



var ssl = false
var ssl_params = null


var user = 'mosquitto64'
var pswd = 'iot64'
var keepalive = 60
var topic = null
var msg = null
var will_qos = 0
var will_retain = false
var will_flag = false
var clean_session=true

var connection = null
var mqtt_timer  = null

#enum connection_status {NONE,CONNECTING,CONNECTED,ERROR}
enum mqtt_status {CONNECT,CONNACK,PUBLISH,PUBACK,PUBREC,PUBREL,PUBCOMP,SUBSCRIBE,SUBACK,UNSUBSCRIBE,UNSUBACK,PINGREQ,PINGRESP,DISCONNECT}

var status_TCP = 0
var status = 0

func _ready():

	mqtt_timer = Timer.new()
	add_child(mqtt_timer)
	mqtt_timer.timeout.connect(_on_MQTT_Timer_timeout)
	mqtt_timer.set_wait_time(1.0)
	mqtt_timer.set_one_shot(false)
	mqtt_timer.start()

	connect_to_server_TCP()

func _process(_delta):
	pass

func set_state(n:int,value:int)->int:
	value  |= (1 << n)
	return value

func get_state(n : int,value: int  )->int:
	var _state : bool = value & (1 << n) !=0
	return 1 if _state else 0  

func connect_to_server_TCP()->void:
	connection=StreamPeerTCP.new()
	connection.connect_to_host(server,port)

func disconnect_from_serveur_TCP()->void:
	connection.disconnect_from_host()

func mqtt_connect()->void:
	var connect_msg = PackedByteArray()
	
	var b0 = 0x10	# CONNECT Packet fixed header 0x10
	var b1 = 10  	# Remaining Length = length of the header (10 bytes) + length of the Payload
	var b2 = 0x00	# Length MSB (0)
	var b3 = 0x04	# Length LSB (4)
	var b4 = "M".to_utf8_buffer()[0]
	var b5 = "Q".to_utf8_buffer()[0]
	var b6 = "T".to_utf8_buffer()[0]
	var b7 = "T".to_utf8_buffer()[0]
	var b8 = 0x04	#Protocol Level = 4 -> 3.1.X  / 5 -> 5
	var b9 = 0x00 #-> Connect Flags
	var b10 = 0x00 #Keep Alive MSB
	var b11 = 0x00 #Keep Alive LSB
	
	if clean_session:
		b9 = set_state(1,b9)

	if will_flag :
		b9 = set_state(2,b9)

	if will_qos > 0 :
		b9 = set_state(3,b9)
	if will_qos ==2 :
		b9 = set_state(4,b9)

	if will_retain :
		b9 = set_state(5,b9)

	if user :
		b9 = set_state(7,b9)
		if pswd :
			b9 =set_state(6,b9)

	if keepalive:
		b10 |= keepalive >> 8
		b11 |= keepalive & 0x00FF


	###### PAYLOAD

	var connect_payload: PackedByteArray

	# client_id
	connect_payload.append(client_id.length() >> 8)
	connect_payload.append(client_id.length() & 0xFF)
	connect_payload.append_array(client_id.to_utf8_buffer())
	b1 += 2 + len(client_id) 

	if user :
		connect_payload.append(user.length() >> 8)
		connect_payload.append(user.length() & 0xFF)
		connect_payload.append_array(user.to_utf8_buffer())
		b1 += 2 + len(user)

		if pswd :
			connect_payload.append(pswd.length() >> 8)
			connect_payload.append(pswd.length() & 0xFF)
			connect_payload.append_array(pswd.to_utf8_buffer())
			b1 += 2 + len(pswd)

	connect_msg = [b0, b1, b2, b3, b4, b5, b6, b7, b8, b9, b10, b11]
	connect_msg.append_array(connect_payload)
	connection.put_data(connect_msg)
	status = mqtt_status.CONNECT
	printt("connect_msg",connect_msg)

func mqtt_subscribe(sub_topic:String,Packet_Identifier=1,qos:int=0)->void:
	
	###TO DO : sub_topic -> list of topic: MSB + LSB + TopicName + Qos + MSB_n + LSB_n +TopicName_n + Qos_n 
	
	var subscribe_msg = PackedByteArray()
	
	var b0 = 0x82	# Subscribe Packet fixed header 0x82
	var b1 = 2 + 2 + sub_topic.length() + 1	# Remaining Length = header (2 bytes) plus the length of the payload.

	subscribe_msg = [b0, b1]

	subscribe_msg.append(Packet_Identifier >> 8)
	subscribe_msg.append(Packet_Identifier & 0xFF)
	
	subscribe_msg.append(sub_topic.length() >> 8)
	subscribe_msg.append(sub_topic.length() & 0xFF)
	subscribe_msg.append_array(sub_topic.to_utf8_buffer())
	
	subscribe_msg.append(qos)
	
	connection.put_data(subscribe_msg)
	printt("subscribe_msg",subscribe_msg)
	status = mqtt_status.SUBSCRIBE

func mqtt_unsubscribe(sub_topic:String,Packet_Identifier=1)->void:
	
	###TO DO : sub_topic -> list of topic: MSB + LSB + TopicName + Qos + MSB_n + LSB_n +TopicName_n + Qos_n 
	
	var unsubscribe_msg = PackedByteArray()
	
	var b0 = 0xA2	# Subscribe Packet fixed header 0xA2
	var b1 = 2 + 2 + sub_topic.length() # Remaining Length = header (2 bytes) plus the length of the payload.

	unsubscribe_msg = [b0, b1]

	unsubscribe_msg.append(Packet_Identifier >> 8)
	unsubscribe_msg.append(Packet_Identifier & 0xFF)
	
	unsubscribe_msg.append(sub_topic.length() >> 8)
	unsubscribe_msg.append(sub_topic.length() & 0xFF)
	unsubscribe_msg.append_array(sub_topic.to_utf8_buffer())
	
	connection.put_data(unsubscribe_msg)
	printt("unsubscribe_msg",unsubscribe_msg)
	status = mqtt_status.UNSUBSCRIBE
	
func mqtt_disconnect()->void:
	var disconnect_msg:PackedByteArray = [0xe0,0x00]
	connection.put_data(disconnect_msg)
	printt("disconnect_msg",disconnect_msg)
	status = mqtt_status.DISCONNECT

func mqtt_ping_request()->void:
	var pingreq_msg:PackedByteArray = [0xc0,0x00]
	connection.put_data(pingreq_msg)
	printt("pingreq_msg",pingreq_msg)
	status = mqtt_status.PINGREQ
	
func mqtt_publish(pub_topic:String,msg:String,DUP_Flag:int=0,qos:int=0,Packet_Identifier:int=1)->void:
	var publish_msg = PackedByteArray()
	
	var b0 = 0x30	# Publish Packet fixed header 0x3. .-> LSB : Flags DUP, QOS(2bit), Retain 
	var b1 = 2 + pub_topic.length() + msg.length()  	# Remaining Length = length of the header (10 bytes) + length of the Payload
	
	printt("Topic len",pub_topic.length())
	printt("Msg len",msg.length() )
	
	if DUP_Flag != 0:
		b0 = set_state(3,b0)

	if qos > 0 :
		b0 = set_state(1,b0)
	if qos ==2 :
		b0 = set_state(2,b0)

	if will_retain :
		b0 = set_state(0,b0)

	publish_msg = [b0, b1]
	
	publish_msg.append(pub_topic.length() >> 8)
	publish_msg.append(pub_topic.length() & 0xFF)
	publish_msg.append_array(pub_topic.to_utf8_buffer())
	
	if qos > 0 : # b1 +=2 ??? a test
		publish_msg.append(Packet_Identifier >> 8)
		publish_msg.append(Packet_Identifier & 0xFF)

###### PAYLOAD	

	publish_msg.append_array(msg.to_utf8_buffer())
	
	
	connection.put_data(publish_msg)
	status = mqtt_status.PUBLISH
	printt("publish_msg",publish_msg)
		
func _on_MQTT_Timer_timeout()-> void:

	if (status_TCP == StreamPeerTCP.STATUS_NONE || status_TCP == StreamPeerTCP.STATUS_CONNECTING) :
		connection.poll()
		status_TCP = connection.get_status( )
		match status_TCP :
			0:
				status_TCP = StreamPeerTCP.STATUS_NONE
			1:
				status_TCP = StreamPeerTCP.STATUS_CONNECTING
			2:
				status_TCP = StreamPeerTCP.STATUS_CONNECTED
				connection.set_no_delay(true) #speed up ? realy ?
				mqtt_connect()
			3:
				status_TCP = StreamPeerTCP.STATUS_ERROR

	if (status ==  mqtt_status.CONNECT):
		if connection.get_available_bytes() >= 0:
			var data = connection.get_data(4)
			if data[0] == 0:
				status =  mqtt_status.CONNACK
				printt("data : ",data[1])
				mqtt_subscribe("testtopic/64",1,0)
			else:
				printt("Error : ",data[0])
	
	if (status ==  mqtt_status.SUBSCRIBE):
		if connection.get_available_bytes() >= 0:
			var data = connection.get_data(5)
			if data[0] == 0:
				status =  mqtt_status.SUBACK
				printt("data : ",data[1])
				mqtt_ping_request()
			else:
				printt("Error : ",data[0])

	if (status ==  mqtt_status.PINGREQ):
		if connection.get_available_bytes() >= 0:
			var data = connection.get_data(2)
			if data[0] == 0:
				status =  mqtt_status.PINGRESP
				printt("data : ",data[1])
				mqtt_unsubscribe("testtopic/1",1)
				
			else:
				printt("Error : ",data[0])

	if (status ==  mqtt_status.PUBLISH):
		if connection.get_available_bytes() >= 0:
			var data = connection.get_data(2)
			if data[0] == 0:
				status =  mqtt_status.PUBACK  #QOS 0 pas de rep, QOS 1 -> PUBACK, QOS 2 -> PUBREC
				printt("data : ",data[1])
				#mqtt_disconnect()
			else:
				printt("Error : ",data[0])
				
	if (status ==  mqtt_status.UNSUBSCRIBE):
		if connection.get_available_bytes() >= 0:
			var data = connection.get_data(2)
			if data[0] == 0:
				status =  mqtt_status.UNSUBACK
				printt("data : ",data[1])
				mqtt_publish("testtopic/64","ENSGTi",0,0,256)
			else:
				printt("Error : ",data[0])
	
	if (status ==  mqtt_status.DISCONNECT):
			disconnect_from_serveur_TCP()
		
