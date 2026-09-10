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

| Cmd Pos | State Pos | Parameter | Values |
|---------|-----------|-----------|--------|
| 32 | 36 | **RF Power** | 0x01=10mW, 0x02=50mW (0x00=? maybe 30mW) |
| 33 | 37 | **(unknown, initial=0x01)** | — |
| 34 | 38 | **Warn AF Peak** | 0x00=off, 0x01=on |
| 35 | 39 | **Warn RF Mute** | 0x00=off, 0x01=on |
| 36 | 40 | **(needs verification)** | initial=0x0c(12), seen: 0x18(24), 0x10(16) |
| 37 | 41 | **(needs verification)** | initial=0x02, changed to 0x01 |
| 38 | 42 | **(needs verification)** | initial=0x02, changed to 0x01 |
| 39 | 43 | **(needs verification)** | initial=0x02, changed to 0x01 |
| 40 | 44 | **(needs verification)** | initial=0x01, changed to 0x05 |

### Parameters still to map (positions 36-40 / state 40-44):
- Auto Lock TX (boolean)
- RX Balance (-12 to +12?)  
- RX Mode (Stereo/Mono)
- RX Limiter
- RX High Boost (boolean)
- RX Squelch

### Subscribe Command (to receive state updates)
60-byte packet: header + IP + zeros, with:
- [40] = 0x04
- [41] = 0x01
- [59] = 0x01

### Init/Keepalive (18 bytes)
`4f 1f f1 ca` + local_ip + local_ip + `01 00 01 01 01 01`

### Capture File
`/Users/andreaslorunser/Desktop/new_wsm.pcapng` — 123MB, contains full WSM session with parameter changes.

### TODO for next session
- Do a controlled capture changing ONE parameter at a time in known order
- Map remaining positions 36-40 to: Auto Lock, RX Balance, RX Mode, RX Limiter, RX High Boost, RX Squelch
- Find 30mW RF Power value (probably 0x00 or between 0x01 and 0x02)
- Implement binary protocol client in Swift
