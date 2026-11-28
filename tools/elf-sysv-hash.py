#!/usr/bin/env python3
"""SysV DT_HASH buckets/chains for ELF TLS imports. Regenerates tlsHash* tables."""
import sys

NAMES = [
    "TLS_client_method",
    "TLS_server_method",
    "SSL_CTX_new",
    "SSL_CTX_free",
    "SSL_CTX_set_verify",
    "SSL_CTX_ctrl",
    "SSL_CTX_load_verify_locations",
    "SSL_CTX_set_default_verify_paths",
    "SSL_CTX_use_certificate_file",
    "SSL_CTX_use_PrivateKey_file",
    "SSL_CTX_check_private_key",
    "SSL_new",
    "SSL_free",
    "SSL_set_fd",
    "SSL_connect",
    "SSL_accept",
    "SSL_read",
    "SSL_write",
    "SSL_shutdown",
    "SSL_get_verify_result",
    "SSL_set1_host",
    "SSL_CTX_set_options",
    "OpenSSL_version_num",
    "SSL_get1_peer_certificate",
    "i2d_X509",
    "X509_free",
    "SHA256",
    "SHA384",
    "SHA512",
]


def elf_hash(name: str) -> int:
    h = 0
    for c in name.encode():
        h = (h << 4) + c
        g = h & 0xF0000000
        if g:
            h ^= g >> 24
        h &= ~g
        h &= 0xFFFFFFFF
    return h


def tables(names, nbucket=32):
    nchain = 1 + len(names)
    buckets = [0] * nbucket
    chains = [0] * nchain
    for i, n in enumerate(names, start=1):
        b = elf_hash(n) % nbucket
        chains[i] = buckets[b]
        buckets[b] = i
    return buckets, chains


def main():
    buckets, chains = tables(NAMES)
    sys.stdout.write("define tlsHashBuckets\n  return " + str(buckets) + "\nend\n")
    sys.stdout.write("define tlsHashChains\n  return " + str(chains) + "\nend\n")
    sys.stdout.write("nchain %d pltrelsz %d\n" % (len(chains), len(NAMES) * 24))


if __name__ == "__main__":
    main()
