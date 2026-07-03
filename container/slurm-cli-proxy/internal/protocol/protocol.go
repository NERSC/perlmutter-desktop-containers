package protocol

import (
	"bufio"
	"encoding/binary"
	"encoding/json"
	"fmt"
	"io"
)

// FrameType defines the type of a frame in the stream.
type FrameType byte

const (
	FrameSTDIN   FrameType = 1
	FrameSTDOUT  FrameType = 2
	FrameSTDERR  FrameType = 3
	FrameSIGNAL  FrameType = 4
	FrameRESIZE  FrameType = 5
	FrameEXIT    FrameType = 6
	FrameERROR   FrameType = 7
)

// Handshake is sent by the client as a single JSON line before streaming frames.
type Handshake struct {
	Cmd   string   `json:"cmd"`
	Args  []string `json:"args"`
	Env   []string `json:"env"`
	Cwd   string   `json:"cwd"`
	TTY   bool     `json:"tty"`
	Cols  int      `json:"cols"`
	Rows  int      `json:"rows"`
}

// ExitPayload communicates the exit status.
type ExitPayload struct {
	Code     int  `json:"code"`
	Signaled bool `json:"signaled"`
}

// SignalPayload communicates a POSIX signal number.
type SignalPayload struct {
	Signal int `json:"signal"`
}

// ResizePayload communicates a TTY resize.
type ResizePayload struct {
	Cols int `json:"cols"`
	Rows int `json:"rows"`
}

// WriteHandshake writes a JSON handshake followed by a newline.
func WriteHandshake(w io.Writer, h Handshake) error {
	// json.Encoder does not append newline by default for a single value; we write manually.
	var buf []byte
	var err error
	buf, err = json.Marshal(h)
	if err != nil {
		return err
	}
	if _, err := w.Write(append(buf, '\n')); err != nil {
		return err
	}
	return nil
}

// ReadHandshake reads a single line and parses JSON handshake.
func ReadHandshake(r *bufio.Reader) (Handshake, error) {
	line, err := r.ReadBytes('\n')
	if err != nil {
		return Handshake{}, err
	}
	var h Handshake
	if err := json.Unmarshal(bytesTrimRightNewline(line), &h); err != nil {
		return Handshake{}, fmt.Errorf("invalid handshake: %w", err)
	}
	return h, nil
}

// WriteFrame writes a frame with type and payload.
func WriteFrame(w io.Writer, t FrameType, payload []byte) error {
	// Frame format: 1 byte type, 4 bytes length (big endian), then payload
	var header [5]byte
	header[0] = byte(t)
	binary.BigEndian.PutUint32(header[1:], uint32(len(payload)))
	if _, err := w.Write(header[:]); err != nil {
		return err
	}
	if len(payload) > 0 {
		if _, err := w.Write(payload); err != nil {
			return err
		}
	}
	return nil
}

// ReadFrame reads a frame and returns its type and payload.
func ReadFrame(r *bufio.Reader) (FrameType, []byte, error) {
	hdr, err := r.Peek(5)
	if err != nil {
		return 0, nil, err
	}
	// consume header
	if _, err := r.Discard(5); err != nil {
		return 0, nil, err
	}
	t := FrameType(hdr[0])
	ln := binary.BigEndian.Uint32(hdr[1:])
	if ln == 0 {
		return t, nil, nil
	}
	payload := make([]byte, ln)
	if _, err := io.ReadFull(r, payload); err != nil {
		return 0, nil, err
	}
	return t, payload, nil
}

// Helper to trim a single trailing newline (\n) for JSON line input.
func bytesTrimRightNewline(b []byte) []byte {
	if len(b) > 0 && b[len(b)-1] == '\n' {
		return b[:len(b)-1]
	}
	return b
}


