// SPDX-License-Identifier: GPL-3.0-only

#include "protocol.h"
#include "sdk_shim.h"
#include "net.h"
#include "kern_rw_fast.h"

/* Server-side limits duplicated from main.c (no cross-source #include) */
#ifndef SERVER_CMD_MAX_TOTAL
#define SERVER_CMD_MAX_TOTAL 0x1000000 /* 16 MiB max per command */
#endif

int kern_base_handle(int fd, struct cmd_packet *packet) {
    (void)packet;
    uint64_t kbase = KERNEL_ADDRESS_DATA_BASE;
    net_send_int32(fd, CMD_SUCCESS);
    net_send_all(fd, &kbase, 8);
    return 0;
}

int kern_read_handle(int fd, struct cmd_packet *packet) {
    struct cmd_kern_read_packet *p = (struct cmd_kern_read_packet *)packet->data;
    if (!p) {
        net_send_int32(fd, CMD_DATA_NULL);
        return 0;
    }

    /* Guard against oversized reads — cap at server max */
    uint32_t length = p->length;
    if (length > SERVER_CMD_MAX_TOTAL) {
        length = SERVER_CMD_MAX_TOTAL;
    }

    void *buf = net_alloc_buffer(length);
    if (!buf) {
        net_send_int32(fd, CMD_DATA_NULL);
        return 1;
    }
    kernel_copyout_fast(p->address, buf, length);
    net_send_int32(fd, CMD_SUCCESS);
    net_send_all(fd, buf, length);
    free(buf);
    return 0;
}

int kern_write_handle(int fd, struct cmd_packet *packet) {
    struct cmd_kern_write_packet *p = (struct cmd_kern_write_packet *)packet->data;
    if (!p) {
        net_send_int32(fd, CMD_DATA_NULL);
        return 0;
    }
    void *buf = net_alloc_buffer(p->length);
    if (!buf) {
        net_send_int32(fd, CMD_DATA_NULL);
        return 1;
    }
    net_send_int32(fd, CMD_SUCCESS);
    net_recv_all(fd, buf, p->length, 1);
    kernel_copyin_fast(buf, p->address, p->length);
    net_send_int32(fd, CMD_SUCCESS);
    free(buf);
    return 0;
}

int kern_handle(int fd, struct cmd_packet *packet) {
    /* Dispatch bulk reads inline — they need special wire handling */
    if (packet->cmd == CMD_KERN_BULK_READ) {
        return kern_bulk_read_handle(fd, packet);
    }

    switch (packet->cmd) {
        case 0xBDCC0001u: return kern_base_handle(fd, packet);
        case 0xBDCC0002u: return kern_read_handle(fd, packet);
        case 0xBDCC0003u: return kern_write_handle(fd, packet);
        default:      return 1;
    }
}

/* CMD_KERN_BULK_READ (0xBDCC0004u) — read N kernel regions in a single connection.
 * Uses the same bulk_region_entry layout as CMD_PROC_BULK_READ (pid field ignored). */
int kern_bulk_read_handle(int fd, struct cmd_packet *packet) {
    struct cmd_bulk_read_header *hdr = (struct cmd_bulk_read_header *)packet->data;
    if (!hdr || hdr->num_regions == 0 || hdr->num_regions > CMD_BULK_MAX_REGIONS) {
        net_send_int32(fd, CMD_DATA_NULL);
        return 1;
    }

    uint16_t num = hdr->num_regions;

    struct bulk_region_entry *regions =
        (struct bulk_region_entry *)((uint8_t *)hdr + sizeof(struct cmd_bulk_read_header));

    void *scratch = net_alloc_buffer(0x10000);
    if (!scratch) {
        net_send_int32(fd, CMD_DATA_NULL);
        return 1;
    }

    net_send_int32(fd, CMD_SUCCESS);
    net_send_all(fd, &num, 2);
    uint16_t zp = 0;
    net_send_all(fd, &zp, 2);

    for (uint16_t i = 0; i < num; i++) {
        uint64_t addr = regions[i].address;
        uint32_t len  = regions[i].length;

        if (len > SERVER_CMD_MAX_TOTAL) len = SERVER_CMD_MAX_TOTAL;

        uint32_t sent = 0;
        while (sent < len) {
            uint32_t chunk = (len - sent > 0x10000) ? 0x10000 : (len - sent);
            memset(scratch, 0, chunk);
            kernel_copyout_fast((intptr_t)addr + sent, scratch, chunk);
            net_send_all(fd, scratch, (int)chunk);
            sent += chunk;
        }

        regions[i].status = (len == 0) ? 1 : 0;
        net_send_all(fd, &regions[i].pid, sizeof(struct bulk_region_entry));
    }

    free(scratch);
    return 0;
}
