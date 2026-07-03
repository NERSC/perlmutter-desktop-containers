package main

import (
	"bufio"
	"encoding/json"
	"flag"
	"fmt"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"path/filepath"
	"strings"
	"syscall"

	"golang.org/x/term"

	"slurm-cli-proxy/internal/common"
	"slurm-cli-proxy/internal/protocol"
)

func main() {
	log.SetFlags(0)

	invoked := filepath.Base(os.Args[0])
	if invoked == "ssh" {
		runSSH(os.Args[1:], "", autoTTY(os.Args[1:]))
		return
	}

	socket := flag.String("socket", "", "Unix socket path (default from env)")
	ttyMode := flag.String("tty", "auto", "TTY mode: auto, always, never")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: ssh-proxy [flags] [ssh args...]\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	wantTTY := autoTTY(flag.Args())
	switch *ttyMode {
	case "always":
		wantTTY = true
	case "never":
		wantTTY = false
	case "auto":
	default:
		log.Fatalf("invalid --tty value: %s", *ttyMode)
	}

	runSSH(flag.Args(), *socket, wantTTY)
}

func runSSH(args []string, socket string, wantTTY bool) {
	sock := socket
	if sock == "" {
		var err error
		sock, err = common.DefaultSSHProxySocketPath()
		if err != nil {
			log.Fatalf("socket path: %v", err)
		}
	}

	runClient(sock, protocol.Handshake{
		Cmd:  "ssh",
		Args: args,
		Env:  os.Environ(),
		Cwd:  mustGetwd(),
		TTY:  wantTTY,
	}, wantTTY)
}

func autoTTY(args []string) bool {
	if !term.IsTerminal(int(os.Stdin.Fd())) {
		return false
	}
	for _, arg := range args {
		if arg == "-T" {
			return false
		}
		if arg == "-t" || arg == "-tt" {
			return true
		}
		if strings.HasPrefix(arg, "-") && !strings.HasPrefix(arg, "--") {
			if strings.Contains(arg[1:], "T") {
				return false
			}
			if strings.Contains(arg[1:], "t") {
				return true
			}
		}
	}
	return true
}

func runClient(sock string, h protocol.Handshake, ttyRequested bool) {
	conn, err := net.Dial("unix", sock)
	if err != nil {
		log.Fatalf("connect to ssh-proxy-server at %s: %v", sock, err)
	}
	defer conn.Close()

	stdin := os.Stdin
	stdout := os.Stdout
	stderr := os.Stderr

	var oldState *term.State
	if ttyRequested && term.IsTerminal(int(stdin.Fd())) {
		st, err := term.MakeRaw(int(stdin.Fd()))
		if err == nil {
			oldState = st
			if h.Cols == 0 || h.Rows == 0 {
				cols, rows, _ := term.GetSize(int(stdin.Fd()))
				h.Cols = cols
				h.Rows = rows
			}
		}
	}
	defer func() {
		if oldState != nil {
			_ = term.Restore(int(stdin.Fd()), oldState)
		}
	}()

	if err := protocol.WriteHandshake(conn, h); err != nil {
		log.Fatalf("handshake: %v", err)
	}

	br := bufio.NewReader(conn)
	bw := bufio.NewWriter(conn)
	exitCh := make(chan int, 1)

	go func() {
		for {
			t, payload, err := protocol.ReadFrame(br)
			if err != nil {
				if !isEOF(err) {
					fmt.Fprintf(stderr, "ssh-proxy: read error: %v\n", err)
				}
				select {
				case exitCh <- 1:
				default:
				}
				return
			}
			switch t {
			case protocol.FrameSTDOUT:
				_, _ = stdout.Write(payload)
			case protocol.FrameSTDERR:
				_, _ = stderr.Write(payload)
			case protocol.FrameEXIT:
				var ep protocol.ExitPayload
				_ = json.Unmarshal(payload, &ep)
				select {
				case exitCh <- ep.Code:
				default:
				}
				return
			case protocol.FrameERROR:
				msg := strings.TrimSpace(string(payload))
				fmt.Fprintf(stderr, "ssh-proxy: server error: %s\n", msg)
				select {
				case exitCh <- 1:
				default:
				}
				return
			}
		}
	}()

	go func() {
		buf := make([]byte, 32*1024)
		for {
			n, err := stdin.Read(buf)
			if n > 0 {
				_ = protocol.WriteFrame(bw, protocol.FrameSTDIN, buf[:n])
				_ = bw.Flush()
			}
			if err != nil {
				return
			}
		}
	}()

	sigc := make(chan os.Signal, 8)
	signal.Notify(sigc, syscall.SIGINT, syscall.SIGTERM, syscall.SIGWINCH)
	go func() {
		for s := range sigc {
			if s == syscall.SIGWINCH && ttyRequested {
				cols, rows, _ := term.GetSize(int(stdin.Fd()))
				_ = protocol.WriteFrame(bw, protocol.FrameRESIZE, mustJSON(protocol.ResizePayload{Cols: cols, Rows: rows}))
				_ = bw.Flush()
				continue
			}
			_ = protocol.WriteFrame(bw, protocol.FrameSIGNAL, mustJSON(protocol.SignalPayload{Signal: int(s.(syscall.Signal))}))
			_ = bw.Flush()
		}
	}()

	code := <-exitCh
	if oldState != nil {
		_ = term.Restore(int(stdin.Fd()), oldState)
		oldState = nil
	}
	os.Exit(code)
}

func mustJSON(v any) []byte {
	b, _ := json.Marshal(v)
	return b
}

func mustGetwd() string {
	wd, err := os.Getwd()
	if err != nil {
		return ""
	}
	return wd
}

func isEOF(err error) bool {
	return err == io.EOF || err == io.ErrUnexpectedEOF
}
