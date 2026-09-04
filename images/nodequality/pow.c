/*
 * nq-pow — find a nonce whose SHA-256 starts with N zero bits.
 *
 * The publish endpoint charges work instead of asking for an account, and the
 * thing paying is a shell script in a container. A shell cannot pay: piping
 * candidates through `sha256sum` costs a process each and manages a few
 * thousand tries a second, so 22 bits would take twenty minutes and 26 would
 * take a working day. This does about ten million a second in one core, which
 * puts the same 22 bits under a second and leaves headroom to raise it.
 *
 * Static, no libraries, ~20 KB in the image — which is why SHA-256 is written
 * out here rather than linked from OpenSSL.
 *
 *   nq-pow <challenge> <bits> [max-seconds]
 *
 * prints the nonce on stdout, or exits 1 having found nothing in time.
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <time.h>

static const uint32_t K[64] = {
	0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
	0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
	0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
	0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
	0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
	0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
	0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
	0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
};

#define ROR(x, n) (((x) >> (n)) | ((x) << (32 - (n))))

/* One block only: the message is a 32-hex challenge, a dot and a decimal
 * nonce, so it never reaches 56 bytes and never needs a second block. */
static void sha256_block(const uint8_t *msg, size_t len, uint32_t out[8])
{
	uint32_t w[64];
	uint8_t b[64] = { 0 };

	memcpy(b, msg, len);
	b[len] = 0x80;
	uint64_t bits = (uint64_t)len * 8;
	for (int i = 0; i < 8; i++)
		b[63 - i] = (uint8_t)(bits >> (8 * i));

	for (int i = 0; i < 16; i++)
		w[i] = (uint32_t)b[i * 4] << 24 | (uint32_t)b[i * 4 + 1] << 16 |
		       (uint32_t)b[i * 4 + 2] << 8 | (uint32_t)b[i * 4 + 3];
	for (int i = 16; i < 64; i++) {
		uint32_t s0 = ROR(w[i - 15], 7) ^ ROR(w[i - 15], 18) ^ (w[i - 15] >> 3);
		uint32_t s1 = ROR(w[i - 2], 17) ^ ROR(w[i - 2], 19) ^ (w[i - 2] >> 10);
		w[i] = w[i - 16] + s0 + w[i - 7] + s1;
	}

	uint32_t h[8] = { 0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
			  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19 };
	uint32_t a = h[0], bb = h[1], c = h[2], d = h[3];
	uint32_t e = h[4], f = h[5], g = h[6], hh = h[7];

	for (int i = 0; i < 64; i++) {
		uint32_t S1 = ROR(e, 6) ^ ROR(e, 11) ^ ROR(e, 25);
		uint32_t ch = (e & f) ^ (~e & g);
		uint32_t t1 = hh + S1 + ch + K[i] + w[i];
		uint32_t S0 = ROR(a, 2) ^ ROR(a, 13) ^ ROR(a, 22);
		uint32_t mj = (a & bb) ^ (a & c) ^ (bb & c);
		uint32_t t2 = S0 + mj;
		hh = g; g = f; f = e; e = d + t1;
		d = c; c = bb; bb = a; a = t1 + t2;
	}

	out[0] = h[0] + a; out[1] = h[1] + bb; out[2] = h[2] + c; out[3] = h[3] + d;
	out[4] = h[4] + e; out[5] = h[5] + f; out[6] = h[6] + g; out[7] = h[7] + hh;
}

static int leading_zero_bits(const uint32_t h[8])
{
	int n = 0;
	for (int i = 0; i < 8; i++) {
		if (h[i] == 0) { n += 32; continue; }
		return n + __builtin_clz(h[i]);
	}
	return n;
}

int main(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: %s <challenge> <bits> [max-seconds]\n", argv[0]);
		return 2;
	}

	const char *chal = argv[1];
	int bits = atoi(argv[2]);
	long limit = argc > 3 ? atol(argv[3]) : 300;

	size_t clen = strlen(chal);
	if (clen == 0 || clen > 40 || bits < 1 || bits > 48) {
		fprintf(stderr, "nq-pow: challenge or difficulty out of range\n");
		return 2;
	}

	uint8_t msg[64];
	memcpy(msg, chal, clen);
	msg[clen] = '.';

	time_t start = time(NULL);
	uint32_t h[8];

	for (uint64_t nonce = 0;; nonce++) {
		/* The digits, written straight into the buffer — sprintf here
		 * costs more than the hash does. */
		char digits[24];
		int n = 0;
		uint64_t v = nonce;
		do { digits[n++] = (char)('0' + (v % 10)); v /= 10; } while (v);
		for (int i = 0; i < n; i++)
			msg[clen + 1 + i] = (uint8_t)digits[n - 1 - i];

		sha256_block(msg, clen + 1 + (size_t)n, h);
		if (leading_zero_bits(h) >= bits) {
			printf("%llu\n", (unsigned long long)nonce);
			return 0;
		}

		/* Checking the clock every hash would cost more than hashing.
		 * A million tries is a tenth of a second. */
		if ((nonce & 0xFFFFF) == 0xFFFFF && time(NULL) - start > limit) {
			fprintf(stderr, "nq-pow: gave up after %lds at %llu tries\n",
				(long)(time(NULL) - start), (unsigned long long)nonce);
			return 1;
		}
	}
}
