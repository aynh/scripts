#!/usr/bin/env -S v -raw-vsh-tmp-prefix ___bin

import common { exec }
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

// ffprobe executes ffprobe command on `filename` and return the streams
fn ffprobe(filename string) []FfprobeStream {
	output := exec(
		prog: 'ffprobe'
		// retrieve streams information in JSON format
		args: ['-loglevel', 'error', '-show_streams', '-print_format', 'json', quoted_path(filename)]
	)

	tmp := json.decode(FfprobeOutput, output) or { panic(err) }
	return tmp.streams
}

// extract_thumbnail extracts thumbnail (attachment with image MIME) from `filename`
// and return the path to the extracted thumbnail
fn extract_thumbnail(filename string) string {
	streams := ffprobe(filename)
	thumbnail_stream := streams.filter(it.tags.mimetype.starts_with('image'))[0] or {
		panic('${filename} does not have thumbnail')
	}

	thumbnail := join_path(vtmp_dir(), thumbnail_stream.tags.filename)
	exec(
		prog: 'ffmpeg'
		// this is the command that dumps the attachment
		args: ['-y', '-dump_attachment:${thumbnail_stream.index}', quoted_path(thumbnail),
			'-i', quoted_path(filename)]
		// fail_ok because this will return non-zero code
		// as it does not have output argument
		fail_ok: true
	)

	defer {
		rm(thumbnail) or { panic(err) }
	}

	cover := join_path(vtmp_dir(), 'cover.jpeg')
	exec(
		prog: 'gm'
		// graphicsmagick's convert is really straightforward
		// image at the 1st argument will be converted into the 2nd argument
		args: ['convert', quoted_path(thumbnail), quoted_path(cover)]
	)

	return cover
}

// create_metadata creates the necessary metadata for OPUS container to show a cover
// (it's not as simple as cover embedding on M4A/MP3 container)
fn create_metadata(filename string) !string {
	path := join_path(vtmp_dir(), 'metadata.dat')
	mut f := create(path)!
	defer {
		f.close()
	}

	// The metadata must starts with ;FFMETADATA followed by a version number
	// ref: https://ffmpeg.org/ffmpeg-formats.html#Metadata-1
	f.writeln(';FFMETADATA1')!
	thumbnail := extract_thumbnail(filename)
	thumbnail_str := read_file(thumbnail)!
	defer {
		rm(thumbnail) or { panic(err) }
	}

	// x is a helper function that converts the input integer `i`
	// into a hexadecimal representation with a minimum width of 8 characters.
	// Any extra space is filled with zeros on the left.
	//
	// The function then decodes the hexadecimal representation into its
	// corresponding byte array, and returns this byte array as a string.
	x := fn (i int) string {
		decoded := hex.decode('${i:08X}') or { panic(err) }
		return decoded.bytestr()
	}

	// description is not really important, you can omit it entirely
	description, mime := 'Cover Artwork', 'image/jpeg'
	// ref: https://xiph.org/flac/format.html#metadata_block_picture
	metadata := x(3) + x(mime.len) + mime + x(description.len) + description + x(0) + x(0) + x(0) +
		x(0) + x(thumbnail_str.len) + thumbnail_str
	// METADATA_BLOCK_PICTURE needs to be base64-encoded
	metadata_base64 := base64.encode_str(metadata)
	f.writeln('METADATA_BLOCK_PICTURE=${metadata_base64}')!

	return path
}

// convert is the main function
fn convert(filename string) {
	streams := ffprobe(filename)
	audio_stream := streams.filter(it.codec_name == 'opus')[0] or {
		panic('${filename} does not have audio stream')
	}

	metadata := create_metadata(filename) or { panic('failed to create metadata file: ${err}') }
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
