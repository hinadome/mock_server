# MQTT

## Summary (learn this first)

**MQTT** (Message Queuing Telemetry Transport) is a lightweight **publish/subscribe** protocol. Clients connect to a **broker**. Publishers send to a **topic**; all subscribers on that topic receive the message. Publishers and subscribers never talk directly.

| Idea | Meaning |
|------|---------|
| Broker | Central router for topics |
| Topic | Hierarchical path (`mqtt/demo`, `sensors/room/temp`) |
| QoS | 0 / 1 / 2 delivery guarantees |
| Best for | IoT, mobile messaging, low bandwidth / flaky networks |
| Not ideal for | CRUD APIs (HTTP); browser-native without a library (SSE/WS) |

**Compared to others:** WebSocket is client↔server. MQTT fans out through a broker to many devices. SSE pushes from one HTTP server to browsers.

## How pub/sub works

```
Publisher --publish mqtt/demo-->  Broker  --mqtt/demo--> Subscriber A
                                    |
                                    +--mqtt/demo--> Subscriber B
```

On this mock, publishing to `mqtt/demo` also auto-replies on `mqtt/demo/response`.

## On this server

| Item | Value |
|------|-------|
| Broker port | **`1883`** (TCP, not HTTP) |
| Demo publish | `mqtt/demo` |
| Demo reply | `mqtt/demo/response` |
| Extra sample | `mqtt/users/created` → `mqtt/users/created/response` |
| Mock file | [`mocks/mqtt.yaml`](../../mocks/mqtt.yaml) |
| Event bus | HTTP/WS `emit` topics are also published to MQTT |

## Try it

Terminal 1 — subscribe first:

```bash
mosquitto_sub -h localhost -p 1883 -t 'mqtt/demo/response' -v
```

Terminal 2 — publish:

```bash
mosquitto_pub -h localhost -p 1883 -t mqtt/demo -m '{"message":"hi"}'
```

Helper: `./examples/mqtt-demo.sh`

Cross-protocol: after `POST /http/orders`, subscribe to the emit topic on MQTT if you map/bridge that topic name (bus publishes the emit topic string as-is).

## Mock configuration

```yaml
# mocks/mqtt.yaml
routes:
  - match: { topic: mqtt/demo }
    response:
      headers:
        reply-topic: mqtt/demo/response
      body:
        message: Custom MQTT mock response
        topic: mqtt/demo
```

When a client publishes to a matched topic, the mock can publish a reply to `reply-topic`.

## Common mistakes

- Using `http://` URLs — MQTT is TCP on **1883**
- Topic case mismatches (`MQTT/Demo` ≠ `mqtt/demo`)
- Publishing before subscribe (non-retained) — you miss the message
- Expecting REST verbs — MQTT has publish/subscribe, not GET/POST

## Production ports

| Exposure | Port |
|----------|------|
| MQTT TLS (preferred) | **8883** (nginx stream → app `:1883`) |
| MQTT cleartext | **1883** (often firewalled on the public internet) |

See [production.md](../production.md).

## Learn more (references)

| Resource | Why read it |
|----------|-------------|
| [mqtt.org](https://mqtt.org/) | Official project site |
| [MQTT 5.0 OASIS](https://docs.oasis-open.org/mqtt/mqtt/v5.0/mqtt-v5.0.html) | Current specification |
| [MQTT 3.1.1 OASIS](https://docs.oasis-open.org/mqtt/mqtt/v3.1.1/os/mqtt-v3.1.1-os.html) | Widely deployed version |
| [HiveMQ MQTT Essentials](https://www.hivemq.com/mqtt-essentials/) | Excellent free series |
| [Eclipse Mosquitto](https://mosquitto.org/) | Broker + CLI tools |
| [AWS — What is MQTT?](https://aws.amazon.com/what-is/mqtt/) | Short overview |
