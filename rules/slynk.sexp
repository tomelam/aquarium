;;; Where the aquarium image listens for Sly (Slynk): loopback only. Port 4007: code-as-data uses 4006 and a standalone
;;; Slynk (com.user.slynk) holds 4005. Any other address makes the image reachable from that network.

(:interface "127.0.0.1" :port 4007)
