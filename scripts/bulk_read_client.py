#!/usr/bin/env python3
"""
Bulk-read helpers for the nicebug fork of ps5debug-NG.
Uses CMD_PROC_BULK_READ (0xBDAA0025) and CMD_KERN_BULK_READ (0xBDCC0004)
to read N memory regions in a single round-trip.

Wire format (both commands, same layout):
  Request:
    struct { uint16_t num_regions; uint16_t _pad; }                 # 4 bytes
    struct { uint32_t pid; uint16_t status; uint16_t _pad;
             uint64_t address; uint32_t length; }  x N             # 20 bytes each

  Response stream (after bit-swapped CMD_SUCCESS):
    uint16_t num_regions, uint16_t _pad                           # echoed header
    For each region in order:
      <length bytes of raw memory>
      struct bulk_region_entry (20 bytes, status trailer)
"""

import socket
import struct
import time

PS5_IP = "192.168.0.13"
PS5_PORT = 744
PACKET_MAGIC = 0xFFAABBCC

CMD_PROC_BULK_READ = 0xBDAA0025
CMD_KERN_BULK_READ = 0xBDCC0004

REGION_ENTRY_SIZE = 20  # 4+2+2+8+4


def bitswap32(x: int) -> int:
    return ((x << 1) & 0xAAAAAAAA) | ((x >> 1) & 0x55555555)


def build_packet(cmd: int, payload: bytes = b"") -> bytes:
    return struct.pack("<III", PACKET_MAGIC, cmd, len(payload)) + payload


def recv_all(sock: socket.socket, n: int, timeout: float = 30.0) -> bytes:
    sock.settimeout(timeout)
    data = bytearray()
    while len(data) < n:
        chunk = sock.recv(n - len(data))
        if not chunk:
            raise ConnectionError("socket closed")
        data += chunk
    return bytes(data)


def recv_status(sock: socket.socket) -> int:
    raw = struct.unpack("<I", recv_all(sock, 4))[0]
    return bitswap32(raw)


def bulk_read(sock: socket.socket, regions: list[tuple], pid: int = 0,
              kernel: bool = False, timeout: float = 30.0) -> list[bytes | None]:
    """
    Read multiple memory regions in one round-trip.

    Parameters:
        sock:     connected TCP socket to ps5debug-NG port 744
        regions:  list of (address, length) tuples
        pid:      process ID (process reads only, ignored for kernel)
        kernel:   if True, use CMD_KERN_BULK_READ instead of CMD_PROC_BULK_READ
        timeout:  socket timeout in seconds

    Returns:
        List of region data bytes, or None for failed reads.
    """
    cmd = CMD_KERN_BULK_READ if kernel else CMD_PROC_BULK_READ
    num = len(regions)

    # Build request body
    body = struct.pack("<HH", num, 0)  # header
    for addr, length in regions:
        body += struct.pack("<IHHQI", pid, 0, 0, addr, length)

    packet = build_packet(cmd, body)
    sock.settimeout(timeout)
    sock.sendall(packet)

    # Read status
    status = recv_status(sock)
    if status != 0x80000000:
        raise RuntimeError(f"bulk read failed with status 0x{status:08X}")

    # Read echoed header
    echo = recv_all(sock, 4)
    echo_num, echo_pad = struct.unpack("<HH", echo)
    assert echo_num == num, f"echoed num {echo_num} != {num}"

    results = []
    for i, (addr, length) in enumerate(regions):
        # Read the raw data for this region
        data = recv_all(sock, length, timeout=timeout)
        results.append(data)

        # Read the status trailer (20 bytes)
        trailer_bin = recv_all(sock, REGION_ENTRY_SIZE, timeout=timeout)
        t_pid, t_status, t_pad, t_addr, t_len = struct.unpack("<IHHQI", trailer_bin)
        if t_status != 0:
            print(f"  [WARN] region {i} (0x{addr:X}) returned status {t_status}")
            results[-1] = None

    return results


def demo():
    """Example: dump 3 process regions from Demon's Souls."""
    pid = 90  # Demon's Souls PID (may vary)
    regions = [
        (0x800000000, 0x10000, "game_code_64k"),
        (0x800000010000, 0x10000, "game_code_next_64k"),
        (0x810000000, 0x1000, "game_data_4k"),
    ]

    sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    sock.connect((PS5_IP, PS5_PORT))
    print(f"Connected to {PS5_IP}:{PS5_PORT}")

    try:
        results = bulk_read(sock, [(r[0], r[1]) for r in regions],
                            pid=pid, timeout=15.0)

        for (addr, length, name), data in zip(regions, results):
            if data is not None:
                print(f"  {name}: {len(data)} bytes, "
                      f"first 16: {data[:16].hex()}")
            else:
                print(f"  {name}: FAILED")
    finally:
        sock.close()


if __name__ == "__main__":
    demo()
