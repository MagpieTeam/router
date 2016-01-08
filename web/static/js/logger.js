// To use Phoenix channels, the first step is to import Socket
// and connect at the socket path in "lib/my_app/endpoint.ex":
import {Socket} from "deps/phoenix/web/static/js/phoenix"

let Logger = {
  id: null,
  socket: null,
  channel: null,
  logging: false,
  delay: null,
  init(id, sensor_ids, delay = 1000) {
    console.log('initing')
    this.id = id
    this.sensor_ids = sensor_ids
    this.delay = delay
  },
  connect(password) {
    console.log("connecting")
    this.socket = new Socket("/sockets/logger", {
      logger: ((kind, msg, data) => { console.log(`${kind}: ${msg}`, data) }),
      params: {"id": this.id, "password": password}
    })
    this.socket.connect()
  },
  start() {
    console.log("start logging")
    this.channel = this.socket.channel("loggers:" + this.id, {})
    this.channel.join()
      .receive("ok", resp => { 
        this.logging = true
        this.log()
      })
  },
  log() {
    if (this.logging) {
      this.timestamp += 1000
      let value = Math.random() * 100
      console.log(this.sensor_ids)
      let measurements = this.sensor_ids.map(sensor_id => {
        return {
          sensor_id: sensor_id,
          timestamp: Date.now().toString(),
          value: value.toString(),
          metadata: "AAAF"
        }
      })
      let log = { measurements: measurements }
      console.log("sending log")
      this.channel.push("new_log", log)
      setTimeout(() => this.log(), this.delay)
    }
  },
  stop() {
    this.logging = false
    this.channel.leave()
      .receive("ok", resp => {
        this.channel = null
      })
  }
}

export default Logger
