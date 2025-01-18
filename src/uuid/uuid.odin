package uuid

import "core:math/rand"

UUID4 :: [36]byte
Guid :: UUID4

init :: proc(u: ^UUID4) #no_bounds_check {
	bytes: [16]byte
	n := rand.read(bytes[:])
	bytes[6] = (bytes[6] & 0x0f) | (4 << 4)
	bytes[8] = (bytes[8]&(0xff>>2) | (0x02 << 6))

	// encode the bytes
	hex(u[0:8], bytes[0:4])
	u[8] = '-'
	hex(u[9:13], bytes[4:6])
	u[13] = '-'
	hex(u[14:18], bytes[6:8])
	u[18] = '-'
	hex(u[19:23], bytes[8:10])
	u[23] = '-'
	hex(u[24:], bytes[10:])	
}

gen :: proc() -> (u: UUID4) {
	init(&u)
	return
}

set :: proc(id: ^UUID4, str: string) {
	copy(id[:], str[:])
}

@private
HEXTABLE := [16]byte {
	'0', '1', '2', '3',
	'4', '5', '6', '7',
	'8', '9', 'a', 'b',
	'c', 'd', 'e', 'f',
}

@private
hex :: proc(dst, src: []byte) #no_bounds_check {
	i := 0
	for v in src {
		dst[i]   = HEXTABLE[v>>4]
		dst[i+1] = HEXTABLE[v&0x0f]
		i+=2
	}
}