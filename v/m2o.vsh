#!/usr/bin/env -S v

import encoding.base64
import encoding.hex
import json
import os

struct FfprobeOutput {
	streams []FfprobeStream
}

struct FfprobeStream {
	index      int
	codec_name string
	tags       struct {
		filename string
		mimetype string
	}
}

[params]
struct ExecParams {
	prog    string
	args    []string
	fail_ok bool
}

fn exec(e ExecParams) string {
	bin := find_abs_path_of_executable(e.prog) or { panic('${e.prog} is not installed') }

	result := execute(bin + ' ' + e.args.join(' '))
	if !e.fail_ok && result.exit_code != 0 {
		panic(result.output)
	}

	return result.output
}

fn ffprobe(filename string) []FfprobeStream {
	args := ['-loglevel', 'error', '-show_streams', '-print_format', 'json', quoted_path(filename)]
	output := json.decode(FfprobeOutput, exec(prog: 'ffprobe', args: args)) or { panic(err) }
	return output.streams
}

fn extract_thumbnail(filename string) string {
	streams := ffprobe(filename)
	thumbnail_stream := streams.filter(it.tags.mimetype.starts_with('image'))[0] or {
		panic('${filename} does not have thumbnail')
	}

	thumbnail := join_path(vtmp_dir(), thumbnail_stream.tags.filename)
	exec(
		prog: 'ffmpeg'
		args: ['-y', '-dump_attachment:${thumbnail_stream.index}', quoted_path(thumbnail),
			'-i', quoted_path(filename)]
		fail_ok: true
	)

	defer {
		rm(thumbnail) or { panic(err) }
	}

	jpeg := join_path(vtmp_dir(), 'cover.jpeg')
	exec(
		prog: 'gm'
		args: ['convert', quoted_path(thumbnail), quoted_path(jpeg)]
	)

	return jpeg
}

fn create_opus_metadata(filename string) !string {
	path := join_path(vtmp_dir(), 'metadata.dat')
	mut f := create(path)!
	defer {
		f.close()
	}

	f.writeln(';FFMETADATA1')!
	thumbnail := extract_thumbnail(filename)
	thumbnail_str := read_file(thumbnail)!
	defer {
		rm(thumbnail) or { panic(err) }
	}

	x := fn (i int) string {
		decoded := hex.decode('${i:08X}') or { panic(err) }
		return decoded.bytestr()
	}

	description, mime := 'Cover Artwork', 'image/jpeg'
	metadata := x(3) + x(mime.len) + mime + x(description.len) + description + x(0) + x(0) + x(0) +
		x(0) + x(thumbnail_str.len) + thumbnail_str
	metadata_base64 := base64.encode_str(metadata)
	f.writeln('METADATA_BLOCK_PICTURE=${metadata_base64}')!

	return path
}

fn convert(filename string) {
	streams := ffprobe(filename)
	audio_stream := streams.filter(it.codec_name == 'opus')[0] or {
		panic('${filename} does not have audio stream')
	}

	metadata := create_opus_metadata(filename) or {
		panic('failed to create metadata file: ${err}')
	}
	defer {
		rm(metadata) or { panic(err) }
	}

	output := filename + '.opus'
	exec(
		prog: 'ffmpeg'
		args: ['-y', '-i', quoted_path(filename), '-i', quoted_path(metadata), '-map',
			'0:${audio_stream.index}', '-map_metadata', '0', '-map_metadata', '1', '-codec', 'copy',
			quoted_path(output)]
	)
}

convert(os.args[1] or { panic('1 argument is required') })
