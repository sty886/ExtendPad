package annexb

import (
	"bytes"
	"testing"
)

func nal(nalType byte, payload string) []byte {
	return append([]byte{(nalType & 0x1F) | 0x60}, []byte(payload)...)
}

func stream(frames int) []byte {
	var buffer bytes.Buffer
	for index := 0; index < frames; index++ {
		buffer.Write(startCode)
		buffer.Write(nal(9, ""))
		if index == 0 {
			buffer.Write(startCode)
			buffer.Write(nal(7, "sps"))
			buffer.Write(startCode)
			buffer.Write(nal(8, "pps"))
		}
		sliceType := byte(1)
		if index == 0 {
			sliceType = 5
		}
		buffer.Write(startCode)
		buffer.Write(nal(sliceType, "slice"))
	}
	return buffer.Bytes()
}

func TestOneUnitPerPicture(t *testing.T) {
	splitter := &Splitter{}
	var units [][]byte
	input := stream(5)
	for index := 0; index < len(input); index += 7 {
		units = append(units, splitter.Feed(input[index:min(index+7, len(input))])...)
	}
	units = append(units, splitter.Flush()...)
	if len(units) != 5 {
		t.Fatalf("got %d units, want 5", len(units))
	}
	for _, unit := range units {
		if !bytes.HasPrefix(unit, startCode) || unit[4]&0x1F != 9 {
			t.Fatalf("unit does not start with AUD: % x", unit[:8])
		}
	}
}

func TestFirstUnitCarriesParameterSets(t *testing.T) {
	splitter := &Splitter{}
	units := append(splitter.Feed(stream(2)), splitter.Flush()...)
	if len(units) == 0 {
		t.Fatal("no units")
	}
	var types []byte
	position := 0
	for {
		index := bytes.Index(units[0][position:], startCode)
		if index < 0 {
			break
		}
		position += index + 4
		types = append(types, units[0][position]&0x1F)
	}
	if len(types) < 3 || types[0] != 9 || types[1] != 7 || types[2] != 8 {
		t.Fatalf("unexpected NAL types: %v", types)
	}
}

func TestThreeByteStartCodesAreNormalised(t *testing.T) {
	splitter := &Splitter{}
	input := append(append([]byte{0x00, 0x00, 0x01}, nal(9, "")...),
		append([]byte{0x00, 0x00, 0x01}, nal(1, "slice")...)...)
	units := append(splitter.Feed(input), splitter.Flush()...)
	if len(units) != 1 {
		t.Fatalf("got %d units", len(units))
	}
	want := append(append(append([]byte{}, startCode...), nal(9, "")...),
		append(startCode, nal(1, "slice")...)...)
	if !bytes.Equal(units[0], want) {
		t.Fatalf("got % x, want % x", units[0], want)
	}
}
