

Stages:
1. Load torrent file
2. Connect to tracker and get peers
3. Connect to peers
4. Download pieces from peers

Tasks:
DownloadTorrent
LoadTorrent
ConnectToTracker
HeartbeatTracker
ConnectToPeer
DownloadPiece
DownloadBlock

Event:
TorrentFileLoaded
TrackerConnected
PeerConnected
BlockDownloaded
PieceDownloaded

EventHandler:
	TorrentFileLoaded:
		iterate over announce-list and run ConnectToTracker on each
	TrackerConnected:
		iterate over peers and run ConnectToPeer on each
		run HeartbeatTracker
	PeerConnected:
		get intersection of torrent needed pieces and peer had pieces,
		randomize pieces, iterate pieces and run DownloadPiece (wait for each piece)
