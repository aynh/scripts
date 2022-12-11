#!/usr/bin/env -S v

import json
import rand

struct Config {
	id           string [required]
	path         string [required]
	audio_only   bool
	match_title  string
	reject_title string
}

fn (c Config) get_ytdlp_args() []string {
	format := if c.audio_only { 'ba[ext=m4a]' } else { 'ba+bv' }

	path := norm_path(c.path)
	archive_path := '${path}/archive'

	return [c.id, '--format=${format}', '--paths=${path}', '--download-archive=${archive_path}',
		'--match-title=${c.match_title}', '--reject-title=${c.reject_title}']
}

fn (c Config) execute() {
	yt_dlp := find_abs_path_of_executable('yt-dlp') or { panic('yt-dlp not installed') }
	mut p := new_process(yt_dlp)
	p.set_args(c.get_ytdlp_args())

	p.run()
	p.wait()
	p.close()
}

fn get_configs() []Config {
	dir := config_dir() or { '.' }
	data := read_file(join_path(dir, 'autoytdlp.json')) or { panic('config not found') }

	return json.decode([]Config, data) or { panic('config is invalid') }
}

fn main() {
	mut configs := get_configs()
	rand.shuffle(mut configs)!

	for config in configs {
		config.execute()
	}
}
