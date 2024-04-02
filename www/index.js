let serverURL;

let socket;
// variables for the DOM elements:
let incomingSpan;
let outgoingText;
let connectionSpan;
let connectButton;

let uploadButton;
let uploadFile;

let root = {
	peers: {},
};

function setup() {
    incomingSpan = document.getElementById('incoming');
    outgoingText = document.getElementById('outgoing');
    connectionSpan = document.getElementById('connection');
    connectButton = document.getElementById('connectButton');
	uploadButton = document.getElementById('uploadButton');
	uploadFile = document.getElementById('uploadFile');

	uploadButton.onclick = async function() {
		let file = uploadFile.files[0];
		let byteFile = await getAsByteArray(file);
		socket.send(byteFile);
	}

    outgoingText.addEventListener('change', sendMessage);
    connectButton.addEventListener('click', changeConnection);
    openSocket("ws://127.0.0.1:8080");
}

function openSocket(url) {
    socket = new WebSocket(url);
    socket.addEventListener('open', openConnection);
    socket.addEventListener('close', closeConnection);
    socket.addEventListener('message', readIncomingMessage);
}

async function getAsByteArray(file) {
  return new Uint8Array(await readFile(file))
}

function readFile(file) {
    return new Promise((resolve, reject) => {
        let reader = new FileReader()

        reader.addEventListener("loadend", e => resolve(e.target.result))
        reader.addEventListener("error", reject)

        reader.readAsArrayBuffer(file)
    });
}

function changeConnection(event) {
    if (socket.readyState === WebSocket.CLOSED) {
        openSocket("ws://127.0.0.1:8080");
    } else {
        socket.close();
    }
}

function openConnection() {
    connectionSpan.innerHTML = "true";
    connectButton.value = "Disconnect";
}

function closeConnection() {
    connectionSpan.innerHTML = "false";
    connectButton.value = "Connect";
}

const TORRENT_ADDED = 0;
const PEER_CONNECTED = 1;
const PEER_DISCONNECTED = 2;
const PEER_STATE_CHANGED = 3;
const PEER_HAVE = 4;

function bitCount (n) {
	n = n - ((n >> 1) & 0x55555555)
	n = (n & 0x33333333) + ((n >> 2) & 0x33333333)
	return ((n + (n >> 4) & 0xF0F0F0F) * 0x1010101) >> 24
}

function bitCountArray (n) {
	var total = 0;
	for (const element of n) {
		total = bitCount(element);
	}
	return total;
}

function readIncomingMessage(event_raw) {
	var element = $('<li>' + event_raw.data + '</li>');
    $('#incoming').append(element);

    ev = JSON.parse(event_raw.data);
	switch(ev.id) {
		//case TORRENT_ADDED: {
		//	addTorrent(ev.data, "#TORRENT CONTENT#");
		//} break;
		case PEER_CONNECTED: {
			addPeer(ev.data);
		} break;
		case PEER_DISCONNECTED: {
			removePeer(ev.data);
		} break;
		//case PEER_UPDATED: {
		//	var piece_count = bitCountArray(ev.peer.remote_pieces);
		//	ev.progress = (bitCountArray(ev.peer.remote_pieces) / ev.total) * 100;
		//	var id = ev.ip[0] + '.' + ev.ip[1] + '.' + ev.ip[2] + '.' + ev.ip[3];
		//	$('#'+id).html(ev.ip + ` <progress id="file" value="`+ ev.progress +`" max="100"> `+ ev.progress +`% </progress> ` + piece_count+`/`+ev.total);
		//} break;
	}
}

function sendMessage() {
    if (socket.readyState === WebSocket.OPEN) {
        socket.send(outgoingText.value);
    }
}

window.addEventListener('load', setup);

var config = {
    content: [{
		type: 'row',
		content: [{
			type: 'component',
			componentName: 'debugPanel',
			componentState: {}
		},
		{
			type: 'component',
			componentName: 'root',
			componentState: {}
		}]
    }]
};

var myLayout = new window.GoldenLayout(config, $('#layoutContainer'));
window.addEventListener('resize', function(event){ myLayout.updateSize(); });

myLayout.registerComponent('debugPanel', function (container, state) {
    container.getElement().html(
		"Connected to server: <span id=\"connection\">false</span><br>" +
		"<input type=\"button\" id=\"connectButton\" value=\"Connect\"><br>" +
		"Outgoing message: <input type=\"text\" id=\"outgoing\"><br>" +
		"Incoming message: <ul id=\"incoming\"></ul><br>" +
		"<input type=\"file\" id=\"uploadFile\" name=\"file\" /><br><br>" +
		"<button id=\"uploadButton\">Upload</button>"
	);
});

myLayout.registerComponent('root', function (container, state) {
    container.getElement().html('<div id=\"rootStruct\"><pre id="root"></pre></div>');
});

myLayout.init();

var addPeer = function (data) {
	root.peers[data.peerId] = data;
	$('#root')[0].innerText = JSON.stringify(root, null, 2);
};

var removePeer = function (data) {
	delete root.peers[data.peerId]
	$('#root')[0].innerText = JSON.stringify(root, null, 2);
};