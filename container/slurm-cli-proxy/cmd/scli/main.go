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
	if invoked != "scli" {
		// Transparent mode: behave like the invoked Slurm command name
		transparent(invoked, os.Args[1:])
		return
	}

	socket := flag.String("socket", "", "Unix socket path (default from env)")
	tty := flag.Bool("tty", false, "Request TTY if possible")
	cols := flag.Int("cols", 0, "TTY columns")
	rows := flag.Int("rows", 0, "TTY rows")
	flag.Usage = func() {
		fmt.Fprintf(os.Stderr, "Usage: scli [flags] <cmd> [args...]\n")
		flag.PrintDefaults()
	}
	flag.Parse()

	if flag.NArg() < 1 {
		flag.Usage()
		os.Exit(2)
	}

	sock := *socket
	if sock == "" {
		var err error
		sock, err = common.DefaultSocketPath()
		if err != nil {
			log.Fatalf("socket path: %v", err)
		}
	}

	runClient(sock, protocol.Handshake{
		Cmd:  flag.Arg(0),
		Args: flag.Args()[1:],
		Env:  os.Environ(),
		Cwd:  mustGetwd(),
		TTY:  *tty,
		Cols: *cols,
		Rows: *rows,
	}, *tty)
}

func transparent(cmdName string, args []string) {
	sock, err := common.DefaultSocketPath()
	if err != nil {
		log.Fatalf("socket path: %v", err)
	}
	// auto-enable TTY when invoked as salloc (interactive) or when --pty is present
	wantTTY := (cmdName == "salloc" || hasPtyFlag(args)) && term.IsTerminal(int(os.Stdin.Fd()))
	runClient(sock, protocol.Handshake{
		Cmd:  cmdName,
		Args: args,
		Env:  os.Environ(),
		Cwd:  mustGetwd(),
		TTY:  wantTTY,
	}, wantTTY)
}

func runClient(sock string, h protocol.Handshake, ttyRequested bool) {
	conn, err := net.Dial("unix", sock)
	if err != nil {
		log.Fatalf("connect to server at %s: %v", sock, err)
	}
	defer conn.Close()

	stdin := os.Stdin
	stdout := os.Stdout
	stderr := os.Stderr

	oldState := (*term.State)(nil)
	if ttyRequested && term.IsTerminal(int(stdin.Fd())) {
		st, err := term.MakeRaw(int(stdin.Fd()))
		if err == nil {
			oldState = st
			if h.Cols == 0 || h.Rows == 0 {
				w, he, _ := term.GetSize(int(stdin.Fd()))
				if h.Cols == 0 {
					h.Cols = w
				}
				if h.Rows == 0 {
					h.Rows = he
				}
			}
		}
	}

	// Send handshake
	if err := protocol.WriteHandshake(conn, h); err != nil {
		log.Fatalf("handshake: %v", err)
	}

	br := bufio.NewReader(conn)
	bw := bufio.NewWriter(conn)

	// Goroutine: read server frames and write to local stdio
	done := make(chan struct{})
	exitCh := make(chan int, 1)
	go func() {
		defer close(done)
		for {
			t, payload, err := protocol.ReadFrame(br)
			if err != nil {
				if !isEOF(err) {
					fmt.Fprintf(stderr, "scli: read error: %v\n", err)
				}
				select { case exitCh <- 1: default: }
				return
			}
			switch t {
			case protocol.FrameSTDOUT:
				_, _ = stdout.Write(payload)
			case protocol.FrameSTDERR:
				_, _ = stderr.Write(payload)
			case protocol.FrameEXIT:
				var ep protocol.ExitPayload
				_ = jsonUnmarshal(payload, &ep)
				select { case exitCh <- ep.Code: default: }
				return
			case protocol.FrameERROR:
				msg := strings.TrimSpace(string(payload))
				fmt.Fprintf(stderr, "scli: server error: %s\n", msg)
				select { case exitCh <- 1: default: }
				return
			}
		}
	}()

	// Forward stdin to server
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

	// Forward signals
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
	}
	<-done
	os.Exit(code)
}

func hasPtyFlag(args []string) bool {
	for _, a := range args {
		if a == "--pty" || a == "-pty" {
			return true
		}
	}
	return false
}

func jsonUnmarshal(b []byte, v any) error {
	return json.Unmarshal(b, v)
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


