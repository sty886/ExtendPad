// Package capture runs ffmpeg: x11grab for capture and libx264 for encode.
//
// Baseline profile and 4:2:0 so every Android MediaCodec decodes it, no
// B-frames, in-band SPS/PPS on every IDR, and an access-unit delimiter so the
// stream can be split into pictures. A keyframe request restarts the encoder;
// x264 cannot be told "emit an IDR now" over its stdin without decoding input
// ourselves, and a restart costs a few hundred milliseconds.
package capture

import (
	"fmt"
	"io"
	"os/exec"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/display"
)

type Config struct {
	Display      *display.Display
	Region       display.Region
	FPS          int
	Bitrate      string
	Preset       string
	OutputWidth  int
	OutputHeight int
}

func (c Config) EncodedSize() (int, int) {
	if c.OutputWidth > 0 && c.OutputHeight > 0 {
		return c.OutputWidth, c.OutputHeight
	}
	return c.Region.Width, c.Region.Height
}

type Encoder struct {
	config Config

	mutex   sync.Mutex
	command *exec.Cmd
	stdout  io.ReadCloser
	done    chan struct{}

	errorMutex sync.Mutex
	errors     []string
}

func New(config Config) *Encoder { return &Encoder{config: config} }

func (e *Encoder) Config() Config { return e.config }

func (e *Encoder) Arguments() []string {
	config := e.config
	region := config.Region
	arguments := []string{
		"-hide_banner", "-loglevel", "error",
		"-f", "x11grab",
		"-draw_mouse", "1",
		"-framerate", strconv.Itoa(config.FPS),
		"-video_size", fmt.Sprintf("%dx%d", region.Width, region.Height),
		"-i", fmt.Sprintf("%s.0+%d,%d", config.Display.Name, region.X, region.Y),
	}
	if width, height := config.EncodedSize(); width != region.Width || height != region.Height {
		arguments = append(arguments, "-vf", fmt.Sprintf("scale=%d:%d:flags=fast_bilinear", width, height))
	}
	arguments = append(arguments,
		"-an",
		"-pix_fmt", "yuv420p",
		"-c:v", "libx264",
		"-preset", config.Preset,
		"-tune", "zerolatency",
		"-profile:v", "baseline",
		"-b:v", config.Bitrate,
		"-maxrate", config.Bitrate,
		"-bufsize", doubleBitrate(config.Bitrate),
		"-g", strconv.Itoa(config.FPS),
		"-keyint_min", strconv.Itoa(config.FPS),
		"-sc_threshold", "0",
		"-x264-params", "aud=1:repeat-headers=1:bframes=0:force-cfr=1",
		"-f", "h264",
		"pipe:1",
	)
	return arguments
}

func (e *Encoder) Start() error {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.stopLocked()

	path, err := exec.LookPath("ffmpeg")
	if err != nil {
		return fmt.Errorf("ffmpeg is not installed")
	}
	command := exec.Command(path, e.Arguments()...)
	command.Env = e.config.Display.Env()
	stdout, err := command.StdoutPipe()
	if err != nil {
		return err
	}
	stderr, err := command.StderrPipe()
	if err != nil {
		return err
	}
	if err := command.Start(); err != nil {
		return err
	}
	done := make(chan struct{})
	go func() {
		_ = command.Wait()
		close(done)
	}()
	go e.drainErrors(stderr)

	e.command = command
	e.stdout = stdout
	e.done = done
	return nil
}

func (e *Encoder) drainErrors(reader io.Reader) {
	buffer := make([]byte, 4096)
	var partial string
	for {
		count, err := reader.Read(buffer)
		if count > 0 {
			partial += string(buffer[:count])
			for {
				index := strings.IndexByte(partial, '\n')
				if index < 0 {
					break
				}
				line := strings.TrimSpace(partial[:index])
				partial = partial[index+1:]
				if line != "" {
					e.recordError(line)
				}
			}
		}
		if err != nil {
			return
		}
	}
}

func (e *Encoder) recordError(line string) {
	e.errorMutex.Lock()
	defer e.errorMutex.Unlock()
	e.errors = append(e.errors, line)
	if len(e.errors) > 20 {
		e.errors = e.errors[len(e.errors)-20:]
	}
}

// LastErrors returns the most recent ffmpeg diagnostics.
func (e *Encoder) LastErrors() []string {
	e.errorMutex.Lock()
	defer e.errorMutex.Unlock()
	return append([]string{}, e.errors...)
}

func (e *Encoder) Read(buffer []byte) (int, error) {
	e.mutex.Lock()
	reader := e.stdout
	e.mutex.Unlock()
	if reader == nil {
		return 0, io.EOF
	}
	return reader.Read(buffer)
}

func (e *Encoder) Running() bool {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	if e.done == nil {
		return false
	}
	select {
	case <-e.done:
		return false
	default:
		return true
	}
}

func (e *Encoder) Restart() error { return e.Start() }

func (e *Encoder) Stop() {
	e.mutex.Lock()
	defer e.mutex.Unlock()
	e.stopLocked()
}

func (e *Encoder) stopLocked() {
	command := e.command
	done := e.done
	e.command = nil
	e.done = nil
	e.stdout = nil
	if command == nil || command.Process == nil {
		return
	}
	_ = command.Process.Signal(syscall.SIGTERM)
	select {
	case <-done:
	case <-time.After(2 * time.Second):
		_ = command.Process.Kill()
		<-done
	}
}

func doubleBitrate(text string) string {
	if strings.HasSuffix(text, "M") {
		if value, err := strconv.ParseFloat(strings.TrimSuffix(text, "M"), 64); err == nil {
			return fmt.Sprintf("%dM", int(value*2))
		}
	}
	if strings.HasSuffix(text, "k") {
		if value, err := strconv.ParseFloat(strings.TrimSuffix(text, "k"), 64); err == nil {
			return fmt.Sprintf("%dk", int(value*2))
		}
	}
	return text
}
