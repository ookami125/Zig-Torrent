struct Handshake {
	u8 protocolNameLen;
	char protocolName[protocolNameLen];
	u8 reserved[8] [[hidden]];
	u8 infohash[20];
	char peerId[20];
};

enum PacketID : u8 {
    CHOKE = 0,
	UNCHOKE,
	INTERESTED,
	NOT_INTERESTED,
	HAVE,
	BITFIELD,
	REQUEST,
	PIECE,
	CANCEL,
};

struct Packet {
	be u32 length;
	if(length > 0) {
		PacketID id;
		if(id == PacketID::PIECE)
		{
			u32 piece;
			u32 offset;
			u8 data[length-8];
		}
		else
		{
			u8 data[length-1];
		}
	}
};

struct Peer {
	Handshake handshake;
	Packet packet[while (!std::mem::eof())];
};

Peer peer @ $;