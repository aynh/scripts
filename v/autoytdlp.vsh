#!/usr/bin/env -S v

import json
import rand

struct Config {
	// anything that works as yt-dlp URL argument
	id string [required]
	// where to save them
	path string [required]
	// whether to only download audio
	audio_only bool
	// same as --match-title in yt-dlp
	match_title string
	// same as --reject-title in yt-dlp
	reject_title string
}

fn (c Config) args() []string {
	// using ext=m4a here as yt-dlp's opus (the default 'best' audio format) cover embedding rarely works
	format := if c.audio_only { 'ba[ext=m4a]' } else { 'ba+bv' }

	path := norm_path(c.path)
	archive_path := '${path}/archive'

	return [c.id, '--format=${format}', '--paths=${path}', '--download-archive=${archive_path}',
		'--match-title=${c.match_title}', '--reject-title=${c.reject_title}']
}

fn (c Config) execute() {
	yt_dlp := find_abs_path_of_executable('yt-dlp') or { panic('yt-dlp not installed') }
	// not using os.execute here because I want to see yt-dlp's output in realtime
	mut p := new_process(yt_dlp)
	p.set_args(c.args())

	p.run()
	p.wait()
	p.close()
}

fn get_configs() []Config {
	dir := config_dir() or { '.' }
	path := join_path(dir, 'autoytdlp.json')
	data := if s := read_file(path) {
		s
		// the config may be in the current directory
	} else if s := read_file('./autoytdlp.json') {
		s
	} else {
		panic('config not found')
	}

	return json.decode([]Config, data) or { panic('config is invalid') }
}

mut configs := get_configs()
rand.shuffle(mut configs)!

for config in configs {
	config.execute()
}
