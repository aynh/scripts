#!/usr/bin/env -S v -raw-vsh-tmp-prefix ___bin run

// ref: https://sar.informatik.hu-berlin.de/research/publications/SAR-PR-2006-05/SAR-PR-2006-05_.pdf

import cli
import hash.crc32
import os
import strconv

const (
	crc_poly  = u32(0xEDB88320)
	crc_inv   = u32(0x5B358FD3)
	final_xor = u32(0xFFFFFFFF)
)

const local_crc32 = crc32.new(int(crc_poly))

fn calculate_new_bytes(old_crc u32, target_crc u32) []u8 {
	mut new_content := u32(0)
	mut t_target_crc := target_crc ^ final_xor
	for i := 0; i < 32; i += 1 {
		if (new_content & 1) != 0 {
			new_content = (new_content >> 1) ^ crc_poly
		} else {
			new_content >>= 1
		}

		if (t_target_crc & 1) != 0 {
			new_content ^= crc_inv
		}

		t_target_crc >>= 1
	}

	new_content ^= (old_crc ^ final_xor)
	return []u8{len: 4, init: u8(new_content >> it * 8)}
}

fn parse_crc32(s string) ?u32 {
	if s.len == 8 {
		if value := strconv.parse_uint(s, 16, 0) {
			return u32(value)
		}
	}

	return none
}

mut app := cli.Command{
	name: 'recrc32.vsh'
	disable_man: true
	required_args: 2
	usage: '<file> <target_crc32>'
	posix_mode: true
	flags: [
		cli.Flag{
			flag: cli.FlagType.bool
			name: 'execute'
			abbrev: 'x'
			description: 'Patches the file.'
		},
	]
	execute: fn (cmd cli.Command) ! {
		path := cmd.args[0]
		if !exists(path) {
			return error('path `${path}` does not exists')
		} else if !is_file(path) {
			return error('path `${path}` is not a file')
		}

		target_crc_str := cmd.args[1]
		target_crc := parse_crc32(target_crc_str) or {
			return error('`${target_crc_str}` is not a valid CRC32 hash')
		}

		mut file_bytes := read_bytes(path)!
		old_crc := local_crc32.checksum(file_bytes)

		if old_crc == target_crc {
			return error('file `${path}` already has `${target_crc:08X}` CRC32 hash')
		}

		new_bytes := calculate_new_bytes(old_crc, target_crc)
		if cmd.flags.get_bool('execute')! {
			mut f := open_append(path)!
			defer {
				f.close()
			}
			f.write(new_bytes) or { return error('failed to patch file `${path}`') }
		} else {
			file_bytes << new_bytes
			new_crc := local_crc32.checksum(file_bytes)
			if new_crc == target_crc {
				eprintln('patched in-memory file have the correct CRC32 hash (${target_crc:08X})')
				eprintln('pass -x or --execute command line switch to patch the file')
			} else {
				return error("patched in-memory file doesn't have the correct CRC32 hash (${target_crc:08X})")
			}
		}
	}
}

app.setup()
app.parse(os.args)
