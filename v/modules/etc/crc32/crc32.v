// Copyright (c) 2019-2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.

// This is a very basic crc32 implementation
// at the moment with no architecture optimizations

// I (aynh) modified this module by adding
// `init` parameter to checksum functions
// (required for buffered checksums to work)
module crc32

// polynomials
pub const (
	ieee       = u32(0xedb88320)
	castagnoli = u32(0x82f63b78)
	koopman    = u32(0xeb31d82e)
)

// The size of a CRC-32 checksum in bytes.
const (
	size = 4
)

struct Crc32 {
mut:
	table []u32
}

[params]
pub struct Crc32Params {
	b    []u8
	init u32
}

fn (mut c Crc32) generate_table(poly int) {
	for i in 0 .. 256 {
		mut crc := u32(i)
		for _ in 0 .. 8 {
			if crc & u32(1) == u32(1) {
				crc = (crc >> 1) ^ u32(poly)
			} else {
				crc >>= u32(1)
			}
		}
		c.table << crc
	}
}

fn (c &Crc32) sum32(p Crc32Params) u32 {
	mut crc := ~p.init
	for i in 0 .. p.b.len {
		crc = c.table[u8(crc) ^ p.b[i]] ^ (crc >> 8)
	}
	return ~crc
}

pub fn (c &Crc32) checksum(p Crc32Params) u32 {
	return c.sum32(p)
}

// pass the polynomial to use
pub fn new(poly int) &Crc32 {
	mut c := &Crc32{}
	c.generate_table(poly)
	return c
}

// calculate crc32 using ieee
pub fn sum(p Crc32Params) u32 {
	c := new(int(crc32.ieee))
	return c.sum32(p)
}
