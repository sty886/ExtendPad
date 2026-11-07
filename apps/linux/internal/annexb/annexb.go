// Package annexb splits a raw H.264 byte stream into access units.
//
// libx264 runs with aud=1, so every access unit starts with a NAL type 9
// delimiter. Start codes are normalised to four bytes, as the protocol
// requires. The final NAL of a read is held back until the next read proves
// it complete (or Flush is called).
package annexb

import "bytes"

var startCode = []byte{0x00, 0x00, 0x00, 0x01}

type Splitter struct {
	buffer  []byte
	pending [][]byte
}

func (s *Splitter) Feed(data []byte) [][]byte {
	s.buffer = append(s.buffer, data...)
	var units [][]byte
	for {
		complete, rest := completeNALs(s.buffer, true)
		if len(complete) == 0 {
			s.buffer = rest
			return units
		}
		s.buffer = rest
		for _, nal := range complete {
			if nalType(nal) == 9 && len(s.pending) > 0 {
				units = append(units, join(s.pending))
				s.pending = nil
			}
			s.pending = append(s.pending, append(append([]byte{}, startCode...), nal...))
		}
	}
}

// Flush emits everything buffered; the stream ended, so the last NAL is whole.
func (s *Splitter) Flush() [][]byte {
	starts := startPositions(s.buffer)
	var units [][]byte
	for index, position := range starts {
		end := len(s.buffer)
		if index+1 < len(starts) {
			end = starts[index+1].offset
		}
		nal := s.buffer[position.offset+position.length : end]
		if len(nal) == 0 {
			continue
		}
		if nalType(nal) == 9 && len(s.pending) > 0 {
			units = append(units, join(s.pending))
			s.pending = nil
		}
		s.pending = append(s.pending, append(append([]byte{}, startCode...), nal...))
	}
	if len(s.pending) > 0 {
		units = append(units, join(s.pending))
		s.pending = nil
	}
	s.buffer = nil
	return units
}

type startPosition struct {
	offset int // where the start code begins
	length int // 3 or 4
}

func startPositions(buffer []byte) []startPosition {
	var positions []startPosition
	index := 0
	for {
		found := bytes.Index(buffer[index:], []byte{0x00, 0x00, 0x01})
		if found < 0 {
			return positions
		}
		found += index
		if found > 0 && buffer[found-1] == 0 {
			positions = append(positions, startPosition{offset: found - 1, length: 4})
		} else {
			positions = append(positions, startPosition{offset: found, length: 3})
		}
		index = found + 3
	}
}

// completeNALs returns every NAL except the last one (which may still be
// arriving) when keepLast is true, plus the buffer starting at that last NAL.
func completeNALs(buffer []byte, keepLast bool) ([][]byte, []byte) {
	starts := startPositions(buffer)
	if len(starts) == 0 {
		return nil, buffer
	}
	limit := len(starts)
	if keepLast {
		limit--
	}
	var nals [][]byte
	for index := 0; index < limit; index++ {
		end := starts[index+1].offset
		nals = append(nals, buffer[starts[index].offset+starts[index].length:end])
	}
	restart := len(buffer)
	if keepLast {
		restart = starts[len(starts)-1].offset
	}
	return nals, buffer[restart:]
}

func nalType(nal []byte) byte {
	if len(nal) == 0 {
		return 0
	}
	return nal[0] & 0x1F
}

func join(nals [][]byte) []byte {
	total := 0
	for _, nal := range nals {
		total += len(nal)
	}
	result := make([]byte, 0, total)
	for _, nal := range nals {
		result = append(result, nal...)
	}
	return result
}
