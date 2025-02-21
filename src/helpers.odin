package src

import oc "core:sys/orca"

oc_open_cmp :: proc(
	path: string,
	rights: oc.file_access,
	flags: oc.file_open_flags,
) -> (
	cmp: oc.io_cmp,
) {
	req := oc.io_req {
		op     = .OPEN_AT,
		open   = {rights, flags},
		buffer = raw_data(path),
		size   = u64(len(path)),
	}

	return oc.io_wait_single_req(&req)
}
