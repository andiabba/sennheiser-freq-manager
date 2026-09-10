# Sennheiser EW 300 IEM G4 Binary Protocol (Port 8133)

## Confirmed from Wireshark captures

### Packet Types
| Direction | Size (data) | Header | Description |
|-----------|-------------|--------|-------------|
| Device→PC | 66 bytes | `ca 80 70 cd` | Full state packet |
| Device→PC | 65 bytes | `ca 80 70 cd` | Full state packet (variant) |
| Device→PC | 40 bytes | various | Status update (~12/sec) |
| Device→PC | 85 bytes | various | Discovery announce |
| PC→Device | 60 bytes | `c1 80 70 cd` | Command (set parameter) |
| PC→Device | 18 bytes | `4f 1f f1 ca` | Init/keepalive (every ~5s) |
| PC→Device | 11 bytes | — | Small command |

### State Packet (66 bytes, header `ca 80 70 cd`)
```
[0-3]   ca 80 70 cd     Header
[4]     08              Fixed
[5-10]  MAC address     (00:1b:66:33:e1:c0)
[11]    01              Fixed
[12-19] Name            8 ASCII chars, space-padded
[20-23] Frequency       kHz, little-endian uint32
[24]    Bank            0-indexed (SSC bank - 1)
[25]    Channel         0-indexed (SSC channel - 1)
[26-35] TX Parameters   (partially mapped, see below)
[36-44] Control params  (mapped from Wireshark, see below)
[45-65] Other params    (unmapped)
```

### Command Packet (60 bytes, header `c1 80 70 cd`)
```
[0-3]   c1 80 70 cd     Header
[4-7]   Source IP        (sender's IP address)
[8-31]  00...           Zeros
[32-40] Value area      Only ONE byte is non-zero (the parameter value)
[41]    01              Write flag (always 0x01)
[42-59] Selector area   Only ONE byte at [value_pos + 19] = 0x01
```

**Key rule: cmd_byte_pos + 4 = state_byte_pos**

### Confirmed Parameter Mapping

| Cmd Pos | State Pos | Parameter | Values | Verified |
|---------|-----------|-----------|--------|----------|
| 30 | 34 | **TX Auto Lock** | 0x00=unlocked, 0x01=locked | Yes (tx autolock.pcapng) |
| 32 | 36 | **RF Power** | 0x00=10mW, 0x01=30mW, 0x02=50mW | Yes |
| 33 | 37 | **Warn AF Peak** | 0x00=off, 0x01=on | Yes (warnings.pcapng) |
| 34 | 38 | **Warn RF Mute** | 0x00=off, 0x01=on | Yes (warnings.pcapng) |
| 35 | 39 | **RX Auto Lock** | 0x00=ignore, 0x01=unlocked, 0x02=locked | Yes (rx auto lock.pcapng) |
| 36 | 40 | **RX Balance** | 0x00=ignore, 0x01-0x1F=value (0x10=center, range -15..+15) | Yes |
| 37 | 41 | **RX Mode** | 0x00=ignore, 0x01=stereo, 0x02=focus | Yes |
| 38 | 42 | **RX Limiter** | 0x00=ignore, 0x01=off, 0x02=-6dB, 0x03=-12dB, 0x04=-18dB | Yes |
| 39 | 43 | **RX High Boost** | 0x00=ignore, 0x01=off, 0x02=on | Yes |
| 40 | 44 | **RX Squelch** | 0x00=ignore, non-zero=value | Yes |

### Sync/Ignore Mechanism
For RX parameters (cmd[35]-cmd[40] / state[39]-state[44]):
- Value `0x00` = parameter is **ignored** (not synced to receiver)
- Any non-zero value = parameter is **synced** with that value
- No separate sync flag bytes exist — the value itself determines sync state

### TX Auto Lock
Position cmd[30] / state[34]. Outside the cmd[32-40] RX parameter range — sits at a lower offset with a gap at cmd[31]/state[35].

### Handshake Sequence
1. Init packet (18 bytes): `4f 1f f1 ca` + IP + IP + `00 00 01 01 01 01`
2. State request (11 bytes): `a4 fd f7 ca` + IP + `01 01 01`
3. Init packet again
4. Registration (14 bytes): `4c 37 ca ce` + IP(reversed) + `ff ff ff ff 01 01`
5. Wait 300ms, then two more state requests

### Init/Keepalive (18 bytes)
`4f 1f f1 ca` + local_ip + local_ip + `01 00 01 01 01 01`
(byte[12] = 0x01 for keepalive, 0x00 for init)

### Capture Files
- `/Users/andreaslorunser/Desktop/new_wsm.pcapng` — full WSM session
- `/Users/andreaslorunser/Desktop/warnings.pcapng` — AF Peak and RF Mute toggle
- `/Users/andreaslorunser/Desktop/rx auto lock.pcapng` — RX Auto Lock toggle
- `/Users/andreaslorunser/Desktop/ignorewsm.pcapng` — sync/ignore behavior

### Capture Files (additional)
- `/Users/andreaslorunser/Desktop/tx autolock.pcapng` — TX Auto Lock toggle

### TODO
- Verify RF Power 30mW value (currently assumed 0x01)
