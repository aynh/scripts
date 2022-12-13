#!/usr/bin/env -S v -raw-vsh-tmp-prefix ___bin run

import cli
import common { exec }
import encoding.base64
import encoding.hex
import json
import os
import rand
import sync.pool

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

// ffprobe executes ffprobe command on `path` and return the streams
fn ffprobe(path string) []FfprobeStream {
	output := exec(
		prog: 'ffprobe'
		// retrieve streams information in JSON format
		args: ['-loglevel', 'error', '-show_streams', '-print_format', 'json', quoted_path(path)]
	)

	tmp := json.decode(FfprobeOutput, output) or { panic(err) }
	return tmp.streams
}

[params]
struct RunConfig {
	path     string [required]
	filename string [required]
	tmpdir   string [required]
	outdir   string [required]
}

// run is the main function
fn run(c RunConfig) {
	streams := ffprobe(c.path)
	audio_stream := streams.filter(it.codec_name == 'opus')[0] or {
		panic('${c.filename} does not have audio stream')
	}

	metadata_path := create_metadata(c) or { panic('failed to create metadata file: ${err}') }

	outpath := join_path(c.outdir, c.filename.replace(file_ext(c.filename), '.opus'))
	exec(
		prog: 'ffmpeg'
		args: ['-y', '-i', quoted_path(c.path), '-i', quoted_path(metadata_path), '-map',
			'0:${audio_stream.index}', '-map_metadata', '0', '-map_metadata', '1', '-codec', 'copy',
			quoted_path(outpath)]
	)
}

// create_metadata creates the necessary metadata for OPUS container to show a cover
// (it's not as simple as cover embedding on M4A/MP3 container)
fn create_metadata(c RunConfig) !string {
	metadata_path := join_path(c.tmpdir, 'metadata.dat')
	mut metadata_file := create(metadata_path)!
	defer {
		metadata_file.close()
	}

	// The metadata must starts with ;FFMETADATA followed by a version number
	// ref: https://ffmpeg.org/ffmpeg-formats.html#Metadata-1
	metadata_file.writeln(';FFMETADATA1')!
	thumbnail_path := extract_thumbnail(c)
	thumbnail_str := read_file(thumbnail_path)!

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
	metadata_file.writeln('METADATA_BLOCK_PICTURE=${metadata_base64}')!

	return metadata_path
}

// extract_thumbnail extracts thumbnail (attachment with image MIME) from `path`
// and return the path to the extracted thumbnail
fn extract_thumbnail(c RunConfig) string {
	streams := ffprobe(c.path)
	thumbnail_stream := streams.filter(it.tags.mimetype.starts_with('image'))[0] or {
		panic('${c.filename} does not have thumbnail')
	}

	thumbnail_path := join_path(c.tmpdir, thumbnail_stream.tags.filename)
	exec(
		prog: 'ffmpeg'
		// this is the command that dumps the attachment
		args: ['-y', '-dump_attachment:${thumbnail_stream.index}', quoted_path(thumbnail_path),
			'-i', quoted_path(c.path)]
		// this will return non-zero code because it does not have output argument
		fail_ok: true
	)

	cover_path := join_path(c.tmpdir, 'cover.jpeg')
	exec(
		prog: 'gm'
		// converts dumped thumbnail into jpeg because webp can't be used
		args: ['convert', quoted_path(thumbnail_path), quoted_path(cover_path)]
	)

	return cover_path
}

mut app := cli.Command{
	name: 'm2o.vsh'
	disable_man: true
	required_args: 1
	usage: '<mkv_file>...'
	posix_mode: true
	flags: [
		cli.Flag{
			flag: cli.FlagType.string
			name: 'outdir'
			abbrev: 'P'
			description: "Sets output directory [default: '.']"
			default_value: ['.']
		},
	]
	execute: fn (cmd cli.Command) ! {
		for arg in cmd.args {
			if !exists(arg) {
				panic('${arg} does not exists')
			}
		}

		outdir := cmd.flags.get_string('outdir')!
		mut pp := pool.new_pool_processor(
			callback: fn [outdir] (mut pp pool.PoolProcessor, idx int, wid int) {
				item := pp.get_item[string](idx)

				tmpdir := join_path(vtmp_dir(), rand.string(6))
				mkdir_all(tmpdir) or { panic('failed to create tmpdir (${tmpdir}): ${err}') }
				defer {
					rmdir_all(tmpdir) or { panic('failed to delete tmpdir (${tmpdir}): ${err}') }
					println('success ${item}')
				}

				run(
					path: item
					filename: file_name(item)
					outdir: outdir
					tmpdir: tmpdir
				)
			}
		)
		pp.work_on_items(cmd.args)
	}
}

app.setup()
app.parse(os.args)
