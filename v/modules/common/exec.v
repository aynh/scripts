module common

import arrays
import os

[params]
pub struct ExecParams {
	// the program name
	prog string
	// program arguments
	args []string
	// whether to panic on nonzero exit code
	fail_ok bool
}

// exec runs `prog` with `args` while capturing stdout
// exec will panic on nonzero exit code if fail_ok is false (the default)
pub fn exec(e ExecParams) string {
	// find_abs_.. will return an error if `prog` does not exists in PATH
	bin := os.find_abs_path_of_executable(e.prog) or { panic('${e.prog} is not installed') }

	// actual execution
	cmds := arrays.concat([bin], ...e.args)
	result := os.execute(cmds.join(' '))
	if !e.fail_ok && result.exit_code != 0 {
		panic(result.output)
	}

	return result.output
}
