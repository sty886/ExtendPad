// Package tlsclient dials the receiver's pinned mutual-TLS listener.
//
// TLS 1.3 only, this sender's long-term P-256 certificate as its client
// identity, and the receiver's leaf SubjectPublicKeyInfo compared byte for
// byte with the stored pin. There is no CA-chain fallback and no plaintext
// retry (PROTOCOL.md 2.1, SECURITY.md).
package tlsclient

import (
	"bytes"
	"crypto/tls"
	"crypto/x509"
	"errors"
	"fmt"
	"net"
	"time"

	"github.com/raiseCatError/ExtendPad/apps/linux/internal/identity"
)

// Certificate is the TLS identity for this sender.
func Certificate(id *identity.Identity) tls.Certificate {
	return tls.Certificate{
		Certificate: [][]byte{id.Cert.Raw},
		PrivateKey:  id.Key,
		Leaf:        id.Cert,
	}
}

// Dial connects to host:port and returns the connection only once the
// negotiated version and the receiver's pin are verified.
func Dial(host string, port int, cert tls.Certificate, pin []byte, timeout time.Duration) (*tls.Conn, error) {
	config := &tls.Config{
		Certificates: []tls.Certificate{cert},
		MinVersion:   tls.VersionTLS13,
		MaxVersion:   tls.VersionTLS13,
		// Chain validation is deliberately replaced by the pin check below.
		InsecureSkipVerify: true,
		VerifyPeerCertificate: func(rawCerts [][]byte, _ [][]*x509.Certificate) error {
			if len(rawCerts) == 0 {
				return errors.New("receiver presented no certificate")
			}
			leaf, err := x509.ParseCertificate(rawCerts[0])
			if err != nil {
				return err
			}
			if !bytes.Equal(leaf.RawSubjectPublicKeyInfo, pin) {
				return errors.New("receiver key does not match its pin")
			}
			return nil
		},
	}

	dialer := net.Dialer{Timeout: timeout}
	address := net.JoinHostPort(host, fmt.Sprintf("%d", port))
	raw, err := dialer.Dial("tcp", address)
	if err != nil {
		return nil, err
	}
	connection := tls.Client(raw, config)
	_ = connection.SetDeadline(time.Now().Add(timeout))
	if err := connection.Handshake(); err != nil {
		_ = connection.Close()
		return nil, fmt.Errorf("TLS: %w", err)
	}
	_ = connection.SetDeadline(time.Time{})
	if version := connection.ConnectionState().Version; version != tls.VersionTLS13 {
		_ = connection.Close()
		return nil, fmt.Errorf("negotiated TLS version %d, not TLS 1.3", version)
	}
	return connection, nil
}
